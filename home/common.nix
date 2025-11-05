{
  pkgs,
  config,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./btop.nix
    ./hostid.nix
    ./vim/default.nix
    ./git.nix
    ./starship.nix
    ./zsh.nix
    ./yubikey-helper.nix
  ];

  home.stateVersion = "22.05";

  programs = {
    bat.enable = true;
    fzf.enable = true;
    gpg = {
      enable = true;
      settings = {
        use-agent = true;
      };
    };
    zsh.enable = true;
    ripgrep.enable = true;
    tmux.enable = true;
  };

  home.packages = with pkgs; [
    pv
    eza
    pwgen
    mosh
    mtr
  ];

  manual.manpages.enable = false;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "*" = {
        controlMaster = "auto";
        controlPersist = "60m";
        serverAliveInterval = 60;
        serverAliveCountMax = 5;
        hashKnownHosts = true;
        forwardAgent = true;
      };
      "trex.satanic.link" = {
        user = "grw";
      };
    };
  };

  programs.htop = {
    enable = true;
    settings =
      {
        delay = 10;
        show_program_path = false;
        show_cpu_frequency = true;
        show_cpu_temperature = true;
        hide_kernel_threads = true;
      }
      // (with config.lib.htop;
        leftMeters [
          (bar "AllCPUs2")
          (bar "Memory")
          (bar "Swap")
        ])
      // (with config.lib.htop;
        rightMeters [
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
