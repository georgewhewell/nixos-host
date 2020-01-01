{ pkgs, config, ... }:

{

  imports = [
    ./i3.nix
    ./alacritty.nix
    ./polybar.nix
    ./rofi.nix
    ./vim.nix
    ./git.nix
    ./zsh.nix
  ];

  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    exa
    ripgrep

    unzip

    docker-compose
    /* spotify */
    /* calibre */
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
      left = [ "AllCPUs" "Memory" "Swap"  ];
      right = [ "Clock" "Uptime" "Tasks" "LoadAverage"  "Battery" ];
    };
  };

  programs.tmux = {
    enable = true;
  };

}
