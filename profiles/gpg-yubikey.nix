{ config, lib, pkgs, ... }:

{

  # Use gpg-agent for ssh
  programs.ssh.startAgent = false;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  environment.shellInit = ''
    gpg-connect-agent /bye
    export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
  '';

  # Enable smart card daemon
  services.pcscd.enable = true;

  # Add pass chrome extension
  programs.browserpass.enable = true;

  # Enable keybase
  services.keybase.enable = true;
  services.kbfs.enable = true;

  # Pass / yubikey utils
  environment.systemPackages = with pkgs; [
    pass
    gnupg
    pkgs.libu2f-host
    yubikey-personalization
  ];

  # give permission on yubikey to users
  services.udev.packages = with pkgs; [
    yubikey-personalization
  ];

}
