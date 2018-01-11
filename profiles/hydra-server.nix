{ config, pkgs, ... }:

let
  stateDir = "/var/lib/hydra";
  run-hydra-vm = pkgs.callPackage ../modules/qemu.nix {
    profile = ../containers/vms/hydra.nix; };
in rec {

  fileSystems."${stateDir}" =
    { device = "bpool/root/hydra";
      fsType = "zfs";
    };

  environment.etc."qemu-ifup" = rec {
    target = "qemu-ifup";
    text = ''
      #!${pkgs.stdenv.shell}
      echo "Executing ${target}"
      echo "Bringing up $1 for bridged mode..."
      ${pkgs.iproute}/bin/ip link set $1 up promisc on
      echo "Adding $1 to br0..."
      ${pkgs.bridge-utils}/bin/brctl addif br0 $1
      sleep 2
    '';
    mode = "0744";
    uid = config.ids.uids.root;
  };

  systemd.services.qemu-hydra = {
    description = "Hydra server";
    after = [ "network.target" "local-fs.target" ];
    wantedBy = ["multi-user.target"];
    script = ''
      cd ${stateDir} && ${run-hydra-vm}/bin/run-hydra-vm
    '';
    reloadIfChanged = false;
    serviceConfig = {
      /*PermissionsStartOnly = true; # preStart must be run as root*/
      /*User = "bitcoin";*/
      /*Nice = 10;*/
    };
  };

}
