{ pkgs, config, ... }:

{

  imports = [
    ./btop.nix
    ./hostid.nix
    # ./vim/default.nix
    ./git.nix
    ./starship.nix
    ./zsh.nix
  ];

  home.stateVersion = "22.05";
  nixpkgs.config.allowUnfree = true;

  programs = {
    bat.enable = true;
    direnv = {
      enable = true;
      enableZshIntegration = true;
    };
    fzf.enable = true;
    gpg.enable = true;
    ripgrep.enable = true;
    tmux.enable = true;
  };

  home.packages = with pkgs; [
    pv
    eza
    pwgen
    docker-compose
    btop
    # mosh
    mtr
  ];

  manual.manpages.enable = false;

  programs.ssh = {
    enable = true;
    controlMaster = "auto";
    controlPersist = "60m";
    serverAliveInterval = 60;
    serverAliveCountMax = 5;
    hashKnownHosts = true;
    forwardAgent = true;
    matchBlocks = {
      "satanic.link" = { };
      "rock5b.satanic.link" = { };
      "trex.satanic.link" = { };
      "nixhost.satanic.link" = { };
      "*.runpod.io".extraOptions = {
        PubkeyAcceptedAlgorithms = "+ssh-rsa";
      };
      "*.satanic.link !localnetwork 192.168.23.0/24".extraOptions = {
        ProxyCommand = "${pkgs.bash}/bin/bash -c \"${pkgs.openssh}/bin/ssh -W $(echo %h | cut -d. -f1):%p grw@satanic.link\"";
      };
    };
  };

  programs.htop = {
    enable = true;
    settings = {
      delay = 10;
      show_program_path = false;
      show_cpu_frequency = true;
      show_cpu_temperature = true;
      hide_kernel_threads = true;
    } // (with config.lib.htop; leftMeters [
      (bar "AllCPUs2")
      (bar "Memory")
      (bar "Swap")
    ]) // (with config.lib.htop; rightMeters [
      (text "Hostname")
      (text "Tasks")
      (text "LoadAverage")
      (text "Uptime")
      (text "Systemd")
    ]);
  };

  programs.password-store = {
    enable = true;
    settings = {
      PASSWORD_STORE_DIR = "${config.xdg.dataHome}/password-store";
    };
  };
}
