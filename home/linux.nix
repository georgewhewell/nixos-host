{ pkgs, config, ... }:

{

  programs.gpg = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    enableExtraSocket = true;
    sshKeys = [ "EEB6A2D42BF04599AFEF0E9C104AB9B2E16AE31D" ];
  };

  services.keybase.enable = true;
  services.kbfs.enable = true;

}
