{ pkgs, config, ... }: {

  imports = [
    <home-manager/nixos>

    ../../profiles/common.nix
    ../../profiles/home.nix
    ../../profiles/development.nix
    ../../profiles/graphical.nix
    ../../profiles/home-manager.nix
  ];

  networking = {
    hostName = "workvm";
    firewall.allowedTCPPorts = [ 5900 ];
    enableIPv6 = false;
    interfaces.eth0 = {
      useDHCP = true;
    };
  };

  boot = {
    kernelPackages = pkgs.lib.mkDefault pkgs.linuxPackages_latest;
    kernelParams = [
      "mitigations=off"
      "panic=30"
    ];
  };

  services.mingetty.autologinUser = "grw";

  virtualisation = {
    cores = 4;
    memorySize = 4000;
    writableStore = true;

    qemu = {
      networkingOptions = [
        "-device virtio-net-pci,netdev=net0"
        "-netdev tap,id=net0,script=/etc/qemu-ifup"
      ];
      options = [
        "-vga virtio"
        "-display gtk,gl=on"
        "--full-screen"
      ];
    };
  };
}
