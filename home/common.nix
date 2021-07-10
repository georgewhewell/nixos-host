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
  programs.direnv = {
    enable = true;
  };

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
    hashKnownHosts = true;
    forwardAgent = true;
  };

  programs.htop = {
    enable = true;
    cpuCountFromZero = true;
    settings = {
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
