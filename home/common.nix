{ pkgs, config, ... }:

{

  imports = [
    ./hostid.nix
    ./graphical.nix
    ./vim.nix
    ./git.nix
    ./zsh.nix
  ];

  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    exa
    ripgrep
    docker-compose
  ];

  programs.ssh = {
    enable = true;
    controlMaster = "auto";
    controlPersist = "60m";
    hashKnownHosts = true;
    forwardAgent = true;
  };

  programs.gpg = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    enableExtraSocket = true;
    pinentryFlavor = "curses";
  };

  services.keybase.enable = true;
  services.kbfs.enable = true;

  programs.password-store = {
    enable = true;
  };

  services.password-store-sync = {
    enable = true;
    frequency = "*:0";
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
