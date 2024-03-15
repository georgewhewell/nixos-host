{ pkgs, lib, config, ... }:

{
  xdg.enable = true;

  services.lorri.enable = true;
  systemd.user.services.lorri.Service = {
    ProtectHome = lib.mkForce "false";
    ProtectSystem = lib.mkForce "full";
  };

  programs.gpg = {
    enable = true;
  };

  home.packages = with pkgs; [
    ccid
    yubikey-manager
    opensc
    pcsctools
  ];
}
