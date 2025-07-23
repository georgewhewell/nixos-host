{pkgs, lib, ...}: {
  # replace crappy mac utils
  home.packages = with pkgs; [
    gnused
    coreutils
  ];

  # Fix GPG agent SSH support on Darwin
  programs.zsh = {
    sessionVariables = {
      SSH_AUTH_SOCK = "$(gpgconf --list-dirs agent-ssh-socket)";
    };
    initContent = lib.mkAfter ''
      # Launch GPG agent if not running
      gpgconf --launch gpg-agent
    '';
  };
  
  # Also configure bash in case some scripts use it
  programs.bash = {
    enable = true;
    sessionVariables = {
      SSH_AUTH_SOCK = "$(gpgconf --list-dirs agent-ssh-socket)";
    };
    initExtra = ''
      gpgconf --launch gpg-agent
    '';
  };
}
