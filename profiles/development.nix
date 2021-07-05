{ config, pkgs, ... }:

{
  boot.kernel.sysctl."fs.inotify.max_user_watches" = "1048576";

  environment.systemPackages = with pkgs; [
    atom
    idea.pycharm-community
    qcachegrind

    fswatch
    screen
    wget
    rsync
    gitAndTools.gitFull
    mosquitto
    rustup
    rls

    xz
    /* unar */
    unzip
    unrar
    file

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

    niv
    morph
    nixpkgs-fmt
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
    package = pkgs.postgresql_13;
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
  security.wrappers.dumpcap = {
    source = "${pkgs.wireshark}/bin/dumpcap";
    permissions = "u+xs,g+x";
    owner = "root";
    group = "wireshark";
  };
}
