{ config, pkgs, lib, ... }:
{
  /*
    hydra: virtualized kvm machine
  */
  imports =
    [
      ../../profiles/common.nix
      ../../profiles/home.nix
      ../../services/hydra.nix
    ];

  virtualisation = {
    graphics = false;
    writableStore = true;
    writableStoreUseTmpfs = false;
    memorySize = 4096;
    cores = 8;
    diskSize = 1024;
    qemu.networkingOptions = [
      "-device virtio-net-pci,netdev=net0"
      "-netdev tap,id=net0,script=/etc/qemu-ifup"
    ];
  };

  networking = {
    hostName = "hydra";
    hostId = "deadbeef";
    useDHCP = true;
  };

  services.nix-serve = {
    enable = true;
    secretKeyFile = "/etc/nix/signing-key.sec";
  };

  nix.buildCores = lib.mkDefault 12;
}
