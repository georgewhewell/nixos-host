{
  config,
  pkgs,
  inputs,
  ...
}: {
  boot.kernel.sysctl."fs.inotify.max_user_watches" = "1048576";
  programs.nix-ld.enable = true;
  services.udev.extraRules = ''
    ATTRS{idVendor}=="0e8d", ENV{ID_MM_DEVICE_IGNORE}="1"
    ATTRS{idVendor}=="6000", ENV{ID_MM_DEVICE_IGNORE}="1"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0e8d", MODE="0666"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="6000", MODE="0666"
    # uhubctl: allow wheel group to control USB hub power (sysfs interface)
    SUBSYSTEM=="usb", DRIVER=="hub", RUN+="${pkgs.bash}/bin/sh -c 'chgrp wheel /sys$env{DEVPATH}/*-port*/disable 2>/dev/null; chmod g+w /sys$env{DEVPATH}/*-port*/disable 2>/dev/null; true'"

    # Sophgo CV181x USB-recovery devices — let user-mode libusb /
    # fastboot claim them without sudo. ModemManager-ignore stops
    # modemmanager from probing the ROM-DL CDC-ACM endpoints (it sees
    # the VID, tries AT commands, corrupts in-flight FIP pushes).
    # See: nixos-nanokvm dev-board USB-recovery boot.
    SUBSYSTEM=="usb", ATTRS{idVendor}=="3346", ENV{ID_MM_DEVICE_IGNORE}="1"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="3346", ATTRS{idProduct}=="1000", MODE="0666", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="3346", ATTRS{idProduct}=="1001", MODE="0666", TAG+="uaccess"
    # mainline U-Boot fastboot gadget (same VID:PID as Android fastboot).
    SUBSYSTEM=="usb", ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="d00d", MODE="0666", TAG+="uaccess"
  '';
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
    uhubctl
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
    android-tools
  ];

  nix = {
    nixPath = ["nixpkgs=${inputs.nixpkgs}"]; # Enables use of `nix-shell -p ...` etc
    registry.nixpkgs.flake = inputs.nixpkgs; # Make `nix shell` etc use pinned nixpkgs
  };

  # services.udev.packages = [pkgs.platformio];

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

  virtualisation = {
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
}
