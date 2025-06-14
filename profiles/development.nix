{
  config,
  pkgs,
  inputs,
  ...
}: {
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
    dool
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

  nix = {
    nixPath = ["nixpkgs=${inputs.nixpkgs}"]; # Enables use of `nix-shell -p ...` etc
    registry.nixpkgs.flake = inputs.nixpkgs; # Make `nix shell` etc use pinned nixpkgs
  };

  services.udev.packages = [pkgs.platformio];

  services.postgresql = {
    package = pkgs.postgresql_17;
    enable = true;
    enableTCPIP = true;
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
      flags = ["--all"];
    };
  };
}
