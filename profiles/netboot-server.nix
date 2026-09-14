{ config, lib, pkgs, network, inputs, ... }:
let
  lanCidr = "${network.vlans.lan.prefix}.0/${toString network.vlans.lan.cidr}";
  wifiCidr = "${network.vlans.wifi.prefix}.0/${toString network.vlans.wifi.cidr}";
  # Point-to-point USB-gadget link used by the nixos-nanokvm dev boards
  # (target 10.55.0.1, this host 10.55.0.2 — lib/protocol.nix there).
  # They mount the store read-only from this export just like the
  # strix netboot clients do.
  nanokvmUsbCidr = "10.55.0.0/24";
  trexIp = network.primaryIp network.hosts.trex;
  port = network.netbootHttpPort;
  httpAuthority =
    if port == 80
    then trexIp
    else "${trexIp}:${toString port}";

  netbootHosts = lib.filterAttrs (_: h: h.netboot or false) network.hosts;
  netbootMacs = h: [ h.mac ] ++ (h.extraMacs or [ ]);

  # iPXE binary fetched by the firmware's UEFI HTTP boot client (the
  # router's dnsmasq hands out its URL). snponly.efi rides the firmware's
  # own SNP driver, so no native NIC driver is needed. The embedded script
  # retries a few times and then exits so the firmware boot order can fall
  # through to local disk if this server is unreachable.
  netbootIpxe = pkgs.ipxe.override {
    additionalTargets = { "bin-x86_64-efi/snponly.efi" = null; };
    embedScript =
      let
        chainUrl = "http://${httpAuthority}/by-mac/\${net0/mac}.ipxe";
      in
      pkgs.writeText "strix-embed.ipxe" ''
        #!ipxe
        dhcp || exit
        chain ${chainUrl} ||
        sleep 3
        chain ${chainUrl} ||
        sleep 3
        chain ${chainUrl} ||
        exit
      '';
  };

  # Firmware PXE loads iPXE with an embedded script that chains to
  # http://trex:<port>/by-mac/<mac>.ipxe; these per-MAC stubs redirect to
  # the host's current netboot.ipxe under /var/lib/strix-netboot.
  byMac = pkgs.linkFarm "strix-netboot-by-mac" (
    lib.concatLists (
      lib.mapAttrsToList
        (
          name: h:
            map
              (mac: {
                name = "${mac}.ipxe";
                path = pkgs.writeText "chain-${name}-${mac}.ipxe" ''
                  #!ipxe
                  chain http://${httpAuthority}/hosts/${name}/netboot.ipxe
                '';
              })
              (netbootMacs h)
        )
        netbootHosts
    )
  );

  stateDir = "/var/lib/strix-netboot";
  firmwareSnapshotStateDir = "/var/lib/strix-firmware-snapshots";

  # Every netboot host's boot image is part of this host's system closure;
  # the tmpfiles rules below point the served symlinks at them on each
  # activation. Deploying this host therefore refreshes what the strix
  # machines boot — one flake evaluation, no separate deploy step — and the
  # images stay GC-rooted for as long as they are being served.
  netbootImages = lib.mapAttrs
    (name: _: inputs.self.nixosConfigurations.${name}.config.system.build.strixNetboot)
    netbootHosts;

  # The Claw receives its kernel/initrd from fuckup over USB, but mounts this
  # host's /nix/store over trusted WiFi. Keep its complete system closure on
  # trex and GC-rooted by the deployed trex generation.
  clawSystem = inputs.self.nixosConfigurations.claw.config.system.build.toplevel;

  # Ad-hoc escape hatch: rebuild a single host's image from a checkout on
  # this machine. Its out-link replaces the deployed symlink until the next
  # activation resets it. Builds against the checkout's flake.lock, so a
  # drifted local path input needs `nix flake lock --update-input <name>
  # --allow-dirty-locks` first.
  strixNetbootUpdate = pkgs.writeShellScriptBin "strix-netboot-update" ''
    set -euo pipefail

    host="''${1:?usage: strix-netboot-update <host> [flake-path]}"
    flake="''${2:-/mnt/Home/src/nixos-config}"

    mkdir -p ${stateDir}
    exec nix --extra-experimental-features 'nix-command flakes' build -L \
      --out-link "${stateDir}/$host" \
      "$flake#nixosConfigurations.$host.config.system.build.strixNetboot"
  '';
in
{
  # Serves diskless strix machines: read-only /nix/store over NFSv4.2 plus the
  # iPXE boot files over HTTP. Strix model storage is separate and travels only
  # over the pinned NVMe/RDMA path configured by the machine module. The model
  # export below remains for non-Strix LAN clients.

  fileSystems."/export/nix-store" = {
    device = "/nix/store";
    fsType = "none";
    options = [ "bind" ];
  };

  fileSystems."/export/strix-models" = {
    device = "/models";
    fsType = "none";
    options = [ "bind" "nofail" ];
    depends = [ "/models" ];
  };

  # Netboot clients have tmpfs roots. Keep their read-only boot-time EFI
  # snapshots on trex so the evidence survives powering the cluster off.
  fileSystems."/export/strix-firmware-snapshots" = {
    device = firmwareSnapshotStateDir;
    fsType = "none";
    options = [ "bind" ];
    depends = [ firmwareSnapshotStateDir ];
  };

  # Activation (not tmpfiles) so the directories exist before systemd
  # starts mount units on boot.
  system.activationScripts.strixNetbootDirs.text = ''
    mkdir -p ${stateDir} ${firmwareSnapshotStateDir} /models
    # NFSv4 clients must traverse the pseudoroot parent before the more
    # specific per-host no_root_squash export takes effect. Permit traversal
    # without allowing directory listing; host directories remain mode 0700.
    chmod 0711 ${firmwareSnapshotStateDir}
    ${lib.concatMapStringsSep "\n"
      (name: ''
        mkdir -p ${firmwareSnapshotStateDir}/${name}
        chmod 0700 ${firmwareSnapshotStateDir}/${name}
        # The existing NFSv4 fsid=0 pseudoroot is all_squash, so a client's
        # root credential reaches nested exports as the anonymous 65534 user.
        # Give that identity ownership of only its host-specific directory.
        chown 65534:65534 ${firmwareSnapshotStateDir}/${name}
      '')
      (builtins.attrNames netbootHosts)}
  '';

  systemd.tmpfiles.rules = [
    "d /models 0755 root root -"
  ] ++ lib.mapAttrsToList
    (name: image: "L+ ${stateDir}/${name} - - - - ${image}")
    netbootImages;

  services.nfs.server.exports = ''
    /export/nix-store      ${lanCidr}(ro,nohide,no_subtree_check) ${wifiCidr}(ro,nohide,no_subtree_check) ${nanokvmUsbCidr}(ro,nohide,no_subtree_check)
    /export/strix-models   ${lanCidr}(ro,nohide,insecure,no_subtree_check)
    # The existing fsid=0 export is all_squash. Export this traversable parent
    # with the same anonymous identity so nested host directories can accept
    # snapshots; the directory itself is 0711 and contains no files.
    /export/strix-firmware-snapshots ${lanCidr}(rw,nohide,all_squash,anonuid=65534,anongid=65534,no_subtree_check)
    ${lib.concatMapStringsSep "\n"
      (name:
        "/export/strix-firmware-snapshots/${name} "
        + "${network.primaryIp netbootHosts.${name}}(rw,sync,nohide,no_subtree_check,root_squash)")
      (builtins.attrNames netbootHosts)}
  '';

  system.extraDependencies = [ clawSystem ];

  services.nginx.virtualHosts."strix-netboot" = {
    # Select this vhost for firmware requests whose Host header is the boot
    # server's literal address while sharing port 80 with the named sites.
    serverAliases = [ trexIp ];
    listen = [
      {
        addr = "0.0.0.0";
        inherit port;
      }
    ];
    locations."/ipxe/" = {
      alias = "${netbootIpxe}/";
    };
    locations."/by-mac/" = {
      alias = "${byMac}/";
    };
    locations."/hosts/" = {
      alias = "${stateDir}/";
      extraConfig = "autoindex on;";
    };
  };

  networking.firewall.allowedTCPPorts = [ port ];

  environment.systemPackages = [ strixNetbootUpdate ];
}
