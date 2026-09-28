{ config, lib, pkgs, network, ... }:
let
  hostName = config.networking.hostName;
  self = network.hosts.${hostName};
  cfg = config.strix.secureBoot;
  netboot = self.netboot or false;
  closure = pkgs.closureInfo { rootPaths = [ config.system.build.toplevel ]; };
  cmdline = "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}"
    + lib.optionalString netboot " nix_registration=${closure}/registration";
in {
  options.strix.secureBoot.enable = lib.mkEnableOption "signed Strix boot artifacts";

  config = lib.mkIf cfg.enable {
    # Only kernel, initrd and their command line enter the UKI. The Nix store
    # stays on the separately selected disk/RDMA/NFS path. Verified runtime
    # is a separate feature, preserved on the secure-boot-integration branch.
    boot.uki.settings.UKI.Cmdline = lib.mkForce cmdline;
    # systemd-stub makes this service applicable, but a network UKI has no
    # writable ESP on which bootctl could update the loader's random seed.
    systemd.services.systemd-boot-random-seed.enable = lib.mkIf netboot false;

    system.build.strixSecureBoot = pkgs.runCommand "strix-secure-boot-${hostName}" {
      nativeBuildInputs = [ pkgs.coreutils pkgs.jq ];
    } ''
      mkdir -p "$out"
      cp ${config.system.build.uki}/${config.system.boot.loader.ukiFile} "$out/boot.efi"
      printf '%s' ${lib.escapeShellArg cmdline} > "$out/cmdline"
      jq -n --arg host ${lib.escapeShellArg hostName} \
        --arg system ${lib.escapeShellArg config.system.build.toplevel} \
        --arg sha256 "$(sha256sum "$out/boot.efi" | cut -d' ' -f1)" \
        --rawfile cmdline "$out/cmdline" \
        '{schema: 1, host: $host, system: $system, sha256: $sha256,
          cmdline: $cmdline, verifiedRuntime: false}' > "$out/manifest.json"
    '';
  };
}
