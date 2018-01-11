{ config, pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    idea.pycharm-community
    kicad
    libpcap
    lshw
    nix-prefetch-git
    openocd
    pciutils
    pgadmin
    saleae-logic
    screen
    usbutils
    wireshark
  ];

  programs.wireshark.enable = true;

  services.udev = {
    packages = [
      pkgs.openocd
    ];
    extraRules = ''
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0925", ATTRS{idProduct}=="3881",
        GROUP="users", MODE="0660" SYMLINK+="salae-logic"

      SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="0483",
        GROUP="users", MODE="0660" SYMLINK+="stm32"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11",
        GROUP="users", MODE="0660" SYMLINK+="stm32-dfu"
    '';
  };

}
