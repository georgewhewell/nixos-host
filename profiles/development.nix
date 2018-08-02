{ config, pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    atom
    idea.pycharm-community
    /* kicad */
    libpcap
    lshw
    nix-prefetch-git
    openocd
    pciutils
    pgadmin
    /* saleae-logic */
    screen
    usbutils
    wireshark
    iperf
    /* arduino-custom */
    /* (eclipses.eclipseWithPlugins {
      eclipse = eclipses.eclipse-cpp;
      jvmArgs = [ "-Xmx2048m" ];
      plugins = with eclipses.plugins;
        [ cdt gnuarmeclipse ];
    }) */
  ];

  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    package = pkgs.postgresql100;
    authentication = ''
      local all all trust
    '';
    extraPlugins = with pkgs; [
      /* (postage.override { postgresql = pkgs.postgresql100; }) */
      (timescaledb.override { postgresql = pkgs.postgresql100; })
    ];
  };

  services.redis = {
    enable = true;
  };

  virtualisation.docker.enable = true;

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
