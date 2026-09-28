{ config, lib, pkgs, network, inputs, mkSecret, ... }:
let
  hosts = lib.filterAttrs (_: host: (host.netboot or false) && (host.strix.secureBoot or false)) network.hosts;
  state = "/var/lib/strix-secure-boot";
  certificate = ../secrets/strix-secure-boot-db.pem;
  key = config.sops.secrets.strix-secure-boot-db-key.path;
  # Router retains verified public boot files across Trex's temporary-root
  # restarts. Trex remains the signing authority and NFS/RDMA storage server.
  baseUrl = "http://${network.controlPlaneIp}/strix-netboot/secure";
  ipxe = (pkgs.ipxe.override {
    enableDefaultPlatformTargets = false;
    additionalTargets = { "bin-x86_64-efi-sb/snponly.efi" = null; };
    firmwareBinary = "snponly.efi";
    embedScript = pkgs.writeText "strix-secure-ipxe-script" ''
      #!ipxe
      dhcp || exit
      chain ${baseUrl}/by-mac/''${net0/mac}.ipxe ||
      sleep 3
      chain ${baseUrl}/by-mac/''${net0/mac}.ipxe || exit
    '';
  }).overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      rm -f "$out/undionly.kpxe.0"
    '';
  });
  byMac = pkgs.linkFarm "strix-secure-boot-selectors" (lib.concatLists (
    lib.mapAttrsToList (name: host: map (mac: {
      name = "${mac}.ipxe";
      path = pkgs.writeText "secure-${name}.ipxe" ''
        #!ipxe
        chain --name @0 ${baseUrl}/${name}/current/boot.efi
      '';
    }) (lib.unique ([ host.mac (host.netbootMac or host.mac) ] ++ (host.extraMacs or [])))) hosts
  ));
  publisher = pkgs.writeShellApplication {
    name = "strix-secure-boot-publish";
    runtimeInputs = [ pkgs.coreutils pkgs.util-linux pkgs.python3 pkgs.openssl pkgs.sbsigntool pkgs.binutils ];
    text = ''
      umask 022
      mkdir -p ${state}/ipxe
      mkdir -p /nix/var/nix/gcroots/strix-secure-boot
      exec 9>${state}/.publish.lock
      flock -n 9
      ${lib.concatMapStringsSep "\n" (name: ''
        python3 ${./secure-boot-publish.py} \
          --bundle ${inputs.self.nixosConfigurations.${name}.config.system.build.strixSecureBoot} \
          --state ${state} --key ${key} --certificate ${certificate}
        # Retaining signed bytes alone would not keep the referenced runtime
        # closure available for a later rollback after Nix garbage collection.
        generation=$(basename "$(readlink -f ${state}/${name}/current)")
        ln -sfnT ${inputs.self.nixosConfigurations.${name}.config.system.build.strixSecureBoot} \
          "/nix/var/nix/gcroots/strix-secure-boot/${name}-$generation"
      '') (builtins.attrNames hosts)}
      stage=$(mktemp ${state}/ipxe/.snponly.XXXXXX)
      trap 'rm -f "$stage"' EXIT
      sbsign --key ${key} --cert ${certificate} --output "$stage" ${ipxe}/snponly.efi
      sbverify --cert ${certificate} "$stage"
      chmod 0644 "$stage"
      mv -T "$stage" ${state}/ipxe/snponly.efi
      ln -sfnT ${byMac} ${state}/by-mac
    '';
  };
in lib.mkIf (hosts != {}) {
  sops.secrets.strix-secure-boot-db-key = mkSecret "strix-secure-boot-db-key" {};
  system.build.strixSecureBootPublisher = publisher;
  environment.systemPackages = [ publisher ];
  system.build.strixSecureBootIpxe = ipxe;
  system.build.strixSecureBootSelectors = byMac;
  system.build.strixSecureBootRecovery = import ./secure-boot-recovery.nix { inherit pkgs; };
  systemd.tmpfiles.rules = [
    "d ${state} 0755 root root -"
  ];
  systemd.services.strix-secure-boot-publish = {
    description = "Sign and publish Strix boot artifacts";
    wantedBy = [ "multi-user.target" ];
    # Secrets normally arrive during activation; this also orders publication
    # correctly when sops-nix's systemd activation is enabled.
    after = [ "sops-install-secrets.service" ];
    unitConfig.RequiresMountsFor = [ state ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0022";
      ExecStart = "${publisher}/bin/strix-secure-boot-publish";
    };
  };
}
