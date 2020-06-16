{ pkgs, config, ... }:

{

  imports = [
    ./hostid.nix
    ./vim.nix
    ./git.nix
    ./zsh.nix
  ];

  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    bat
    pv
    exa
    ripgrep
    pwgen
    docker-compose
  ];

  programs.ssh = {
    enable = true;
    controlMaster = "auto";
    controlPersist = "60m";
    hashKnownHosts = true;
    forwardAgent = true;
  };

  programs.htop = {
    enable = true;
    cpuCountFromZero = true;
    meters = {
      left = [ "AllCPUs" "Memory" "Swap" ];
      right = [ "Clock" "Uptime" "Tasks" "LoadAverage" "Battery" ];
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
