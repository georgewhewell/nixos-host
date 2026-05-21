{
  pkgs,
  config,
  lib,
  inputs,
  network,
  ...
}: {
  imports = [
    ./btop.nix
    ./hostid.nix
    ./starship.nix
    ./zsh.nix
  ];

  home.stateVersion = "22.05";

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.cache/cargo/bin"
  ];

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
    tmux = {
      enable = true;
      mouse = true;
      extraConfig = ''
        set -g set-clipboard on
      '';
    };
  };

  # Minimal vim for headless - neovim doesn't cross-compile (luajit/nlua0 issue)
  # vim/default.nix overrides with neovim for dev machines
  home.sessionVariables = {
    EDITOR = lib.mkDefault "vim";
    VISUAL = lib.mkDefault "vim";
  };

  home.packages = with pkgs; [
    vim-minimal
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
      ${network.publicFqdn "trex"} = {
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
}
