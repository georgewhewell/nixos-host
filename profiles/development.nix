{ config, pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    idea.pycharm-community
    
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
    screen
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

}
