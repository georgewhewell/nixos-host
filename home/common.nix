{ pkgs, config, ... }:

{

  imports = [
    ./hostid.nix
    ./vim.nix
    ./git.nix
    ./zsh.nix
  ];

  nixpkgs.config.allowUnfree = true;
  xdg.enable = true;

  services.lorri.enable = true;
  programs.direnv.enable = true;

  home.packages = with pkgs; [
    bat
    pv
    exa
    ripgrep
    pwgen
    docker-compose
    tmux
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
      "ax101.satanic.link" = {
        hostname = "ax101.satanic.link";
      };
    };
  };

  programs.htop = {
    enable = true;
    settings = {
      cpu_count_from_zero = true;
      left_meters = [ "AllCPUs" "Memory" "Swap" ];
      right_meters = [ "Clock" "Uptime" "Tasks" "LoadAverage" "Battery" ];
    };
  };

  programs.tmux = {
    enable = true;
  };

  programs.password-store = {
    enable = true;
    settings = {
      PASSWORD_STORE_DIR = "${config.xdg.dataHome}/password-store";
    };
  };
}
