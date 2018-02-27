{ config, pkgs, lib, ... }:
{
  /*
    hydra: virtualized kvm machine
  */
  imports =
    [
      ../../profiles/home.nix
      ../../profiles/nas-mounts.nix
      ../../services/hydra.nix
    ];

  programs.ssh.extraConfig = ''
    Host *.4a
      # todo..
      StrictHostKeyChecking no
  '';

  boot.kernelPackages = pkgs.linuxPackages_latest;

  virtualisation = {
    graphics = false;
    memorySize = 16 * 1024;
    cores = 8;
    writableStore = true;
    diskSize = 1024 * 1024;
    writableStoreUseTmpfs = false;
    diskImage = "/dev/zvol/bpool/qemu/hydra";
    useBootLoader = false;
    qemu.diskInterface = "virtio";
    qemu.networkingOptions = [
      "-device virtio-net-pci,netdev=net0"
      "-netdev tap,id=net0,script=/etc/qemu-ifup"
    ];
  };

  networking = {
    hostName = "hydra";
    hostId = "deadbeef";
    useNetworkd = true;
    useDHCP = true;
  };

  fileSystems."/".options = [
    "noatime"
  ];

  fileSystems."/mnt/Home" =
    { device = "nixhost.4a:/home";
      fsType = "nfs";
    };

  nix.gc = {
    automatic = true;
    options = "--delete-older-than 2w";
    dates = "02:00";
  };

  nix.maxJobs = lib.mkDefault 4;

}
