{ config, pkgs, ... }:

let
  stateDir = "/mnt/hydra";
  run-hydra-vm = pkgs.callPackage ../modules/qemu.nix {
    profile = ../containers/vms/hydra.nix; };
in {

  /*fileSystems."/var/lib/hydra" =
    { device = "bpool/root/hydra";
      fsType = "zfs";
    };*/

  systemd.services.qemu-hydra = {
    description = "Hydra server";
    after = [ "network.target" "local-fs.target" ];
    wantedBy = ["multi-user.target"];
    preStart = ''
      mkdir -p ${stateDir}
      #chown hydra ${stateDir}
    '';
    script = ''
      ${run-hydra-vm}/bin/run-hydra-rm
    '';
    serviceConfig = {
      /*PermissionsStartOnly = true; # preStart must be run as root*/
      /*User = "bitcoin";*/
      /*Nice = 10;*/
    };
  };

}
