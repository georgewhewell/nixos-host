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

  nix.gc = {
    automatic = true;
    # 100GB free space
    options = ''--max-freed "$((100 * 1024**3 - 1024 * $(df -P -k /nix/store | tail -n 1 | ${pkgs.gawk}/bin/awk '{ print $4 }')))"'';
    dates = "05:15";
  };

  nix.maxJobs = lib.mkDefault 8;

}
