{ config, pkgs, ... }:

{
  boot.kernel.sysctl."fs.inotify.max_user_watches" = "1048576";
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    fswatch
    screen
    wget
    rsync

    xz
    unzip
    #unrar
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
    nixpkgs-fmt
    nix-prefetch-git
    nixos-option
    screen
  ];

  environment.etc."nixpkgs".source = pkgs.nixpkgs_src;
  nix.nixPath = [
    "nixpkgs=/etc/nixpkgs"
  ];

  services.udev.packages = [ pkgs.platformio ];

  services.postgresql = {
    package = pkgs.postgresql_14;
    enable = true;
    enableTCPIP = true;
    # extraPlugins = with pkgs.postgresqlPackages; [
    #   timescaledb
    # ];
  };

  services.redis = {
    servers.default = {
      enable = true;
    };
  };

  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      flags = [ "--all" ];
    };
  };

}
