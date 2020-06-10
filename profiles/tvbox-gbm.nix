{ config, pkgs, lib, ... }:

{

  users.users.grw.extraGroups = [ "input" "pulse" ];

  sound.enable = true;

  # dont need this- interferes with kodi
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  security.polkit.enable = true;
  services.upower.enable = true;

  boot.plymouth.enable = false;

  nixpkgs.config.kodi = {
    enablePVRHTS = true;
  };
/*
  services.xserver = {
    enable = true;
    videoDriver = "modesetting";
    desktopManager.kodi.enable = true;
    displayManager.sddm = {
      enable = true;
      autoLogin.enable = true;
      autoLogin.user = "grw";
    };
  }; */

  systemd.services.kodi-gbm = {
    wants = [ "network-online.target" "polkit.service" ];
    conflicts = [ "getty@tty1.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.kodi-gbm}/bin/kodi --standalone";
      StandardInput = "tty";
      StandardOutput = "tty";
      TTYPath = "/dev/tty1";
      PAMName = "login";
      User = "grw";
    };
  };

  networking.firewall.allowedTCPPorts = [ 8080 ];

  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [ libva libva-v4l2-request ];
  };

  environment.systemPackages = with pkgs; [
    libva-utils
    v4l-utils
    mpv
  ];

}
