{ config, pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    atom
    idea.pycharm-community
    pgadmin

    screen
    wget
    rsync
    gitAndTools.gitFull

    xz
    p7zip
    unzip
    unrar

    iperf
    vnstat
    iotop
    nethogs
    ncdu
    dstat
    arp-scan
    libpcap
    wireshark

    lshw
    usbutils
    pciutils
    wirelesstools
    psmisc
    psutils
    pwgen
    jq

    morph
    nix-prefetch-git

    /* screen */
    /* openocd */
    /* saleae-logic */
    /* kicad-unstable */
    #arduinoWithPackages (apkgs: with apkgs; [
    #  esp32 esp8266 BLE spiflash ])
    /* (eclipses.eclipseWithPlugins {
      eclipse = eclipses.eclipse-cpp;
      jvmArgs = [ "-Xmx2048m" ];
      plugins = with eclipses.plugins;
        [ cdt gnuarmeclipse ];
    }) */
  ];

  users.extraUsers.grw = {
    shell = pkgs.zsh;
  };

  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    authentication = ''
      host all all 0.0.0.0/0 trust
    '';
    extraPlugins = with pkgs; [
      timescaledb
    ];
  };

  services.redis = {
    enable = true;
  };

  virtualisation.docker.enable = true;

  programs.wireshark.enable = true;

  /*
  services.udev = {
    packages = [
      pkgs.openocd
    ];
    extraRules = ''
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0925", ATTRS{idProduct}=="3881",
        GROUP="users", MODE="0660", SYMLINK+="salae-logic"

      SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="0483",
        GROUP="users", MODE="0660", SYMLINK+="stm32"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11",
        GROUP="users", MODE="0660", SYMLINK+="stm32-dfu"
    '';
  };
  */

}
