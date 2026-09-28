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
  netbootHosts = lib.filterAttrs (_: h: h.netboot or false) network.hosts;
  storage = import ../machines/x86/trex/spdk-storage-constants.nix;
  rdmaAddress = network.ipOf "fabric" network.hosts."trex-rdma".addresses.fabric;

  netbootExport = pkgs.writeShellApplication {
    name = "spdk-netboot-export";
    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.spdk-ublk ];
    text = ''
      rpc() {
        timeout 30s spdk-rpc -s ${storage.rpcSocket} "$@"
      }

      # The models exporter initializes the shared RDMA transport first.
      rpc nvmf_get_transports | jq -e 'any(.[]; .trtype == "RDMA")' >/dev/null

      ${lib.concatMapStringsSep "\n" (hostName:
        let volume = storage.netbootVolume hostName;
        in ''
          if ! rpc bdev_get_bdevs | jq -e \
            'any(.[]; (.aliases // []) | index("${storage.lvstore}/${volume.name}"))' >/dev/null; then
            rpc bdev_lvol_create -l ${storage.lvstore} -t \
              ${volume.name} ${toString volume.sizeMiB} >/dev/null
          fi
          bdev_uuid=$(rpc bdev_get_bdevs -b ${storage.lvstore}/${volume.name} | jq -er '.[0].uuid')
          if ! rpc nvmf_get_subsystems | jq -e \
            'any(.[]; .nqn == "${volume.nqn}")' >/dev/null; then
            rpc nvmf_create_subsystem ${volume.nqn} -s ${volume.serial} >/dev/null
          fi
          subsystem=$(rpc nvmf_get_subsystems | jq -e '.[] | select(.nqn == "${volume.nqn}")')
          if ! jq -e '.hosts | any(.nqn == "nqn.2026-07.link.satanic:${hostName}")' <<<"$subsystem" >/dev/null; then
            rpc nvmf_subsystem_add_host ${volume.nqn} nqn.2026-07.link.satanic:${hostName} >/dev/null
          fi
          if jq -e '.namespaces | length == 0' <<<"$subsystem" >/dev/null; then
            rpc nvmf_subsystem_add_ns ${volume.nqn} "$bdev_uuid" -n 1 -u ${volume.uuid} >/dev/null
          else
            # Never replace a namespace under a running host's store.
            jq -e --arg bdev "$bdev_uuid" \
              '.namespaces | length == 1 and .[0].bdev_name == $bdev and .[0].uuid == "${volume.uuid}"' \
              <<<"$subsystem" >/dev/null
          fi
          if ! jq -e '.listen_addresses | any(.trtype == "RDMA" and .traddr == "${rdmaAddress}" and .trsvcid == "4420")' \
            <<<"$subsystem" >/dev/null; then
            rpc nvmf_subsystem_add_listener ${volume.nqn} -t RDMA -a ${rdmaAddress} -s 4420 >/dev/null
          fi
          echo "${hostName}: private ${toString (volume.sizeMiB / 1024)} GiB netboot volume ready"
        '') (builtins.attrNames netbootHosts)}
    '';
  };

  firmwareSnapshotStateDir = "/var/lib/strix-firmware-snapshots";

  # The Claw receives its kernel/initrd from fuckup over USB, but mounts this
  # host's /nix/store over trusted WiFi. Keep its complete system closure on
  # trex and GC-rooted by the deployed trex generation.
  clawSystem = inputs.self.nixosConfigurations.claw.config.system.build.toplevel;
in
{
  imports = [ ./secure-boot-server.nix ];
  assertions = [ {
    assertion = lib.all (h: h.strix.secureBoot or false) (builtins.attrValues netbootHosts);
    message = "All Strix netboot clients must enable firmware Secure Boot.";
  } ];

  # Signed iPXE loads a signed UKI over HTTP. Each Strix copies its system
  # closure from NFS into its freshly formatted private NVMe/RDMA volume.
  # Model storage uses the separate pinned read-only snapshot.

  systemd.services.spdk-netboot-export = {
    description = "Export private disposable Strix Nix stores over NVMe/RDMA";
    after = [ "spdk-storage-assemble.service" "spdk-models-export.service" ];
    wants = [ "spdk-models-export.service" ];
    bindsTo = [ "spdk-storage-assemble.service" ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "300s";
      ExecStart = "${netbootExport}/bin/spdk-netboot-export";
    };
  };
  systemd.timers.spdk-netboot-export = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5s";
      OnUnitInactiveSec = "10s";
      Unit = "spdk-netboot-export.service";
    };
  };

  fileSystems."/export/nix-store" = {
    device = "/nix/store";
    fsType = "none";
    options = [ "bind" ];
  };

  fileSystems."/export/strix-models" = {
    device = "/models";
    fsType = "none";
    options = [ "bind" "x-systemd.wanted-by=models.mount" ];
    depends = [ "/models" ];
  };

  # SPDK can become ready after NFS starts. Follow the recovered mount and
  # publish it without restarting NFS or interrupting clients copying stores.
  systemd.services.strix-models-nfs-export = {
    wantedBy = [ "export-strix\\x2dmodels.mount" ];
    bindsTo = [ "export-strix\\x2dmodels.mount" ];
    after = [ "export-strix\\x2dmodels.mount" "nfs-server.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.nfs-utils}/bin/exportfs -ra";
    };
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
  system.activationScripts.strixNetbootDirs = {
    deps = [ "etc" ];
    text = ''
      mkdir -p ${firmwareSnapshotStateDir} /models
      # Remove only the former public raw-boot links; keep signed generations
      # and all storage volumes and firmware snapshots.
      ${lib.concatMapStringsSep "\n"
        (name: "rm -f /var/lib/strix-netboot/${name}")
        (builtins.attrNames netbootHosts)}
      rm -f /var/lib/strix-netboot/secure
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
  };

  systemd.tmpfiles.rules = [
    "d /models 0755 root root -"
  ];

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
    locations."/hosts/secure/" = {
      alias = "/var/lib/strix-secure-boot/";
    };
  };

  networking.firewall.allowedTCPPorts = [ port ];
}
