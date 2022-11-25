{ config, pkgs, ... }:

{
  imports = [
    ./system.nix
  ];

  users.users."grw" = {
    shell = pkgs.zsh;
    home = "/Users/grw";
  };

  environment.systemPackages = [
    pkgs.kitty
  ];

  home-manager.users.grw = { ... }: {
    imports = [
      ../../home/common.nix
      ../../home/darwin.nix
    ];
  };

  # Used for backwards compatibility, please read the changelog before changing.
  system.stateVersion = 3;
  services.nix-daemon.enable = true;

  nix.nixPath = [
      "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs"
          "darwin-config=$HOME/.nixpkgs/darwin-configuration.nix"
          "darwin=$HOME/.nix-defexpr/channels/darwin"
          "$HOME/.nix-defexpr/channels"
    ];

  programs.zsh.enable = true;

  system.activationScripts.applications.text = pkgs.lib.mkForce (''
      echo "setting up ~/Applications/Nix..."
      rm -rf ~/Applications/Nix
      mkdir -p ~/Applications/Nix
      chown grw ~/Applications/Nix
      find ${config.system.build.applications}/Applications -maxdepth 1 -type l | while read f; do
        src="$(/usr/bin/stat -f%Y $f)"
        appname="$(basename $src)"
        osascript -e "tell app \"Finder\" to make alias file at POSIX file \"/Users/grw/Applications/Nix/\" to POSIX file \"$src\" with properties {name: \"$appname\"}";
    done
  '');

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    settings = {
      max-jobs = 4;
      build-cores = 0;
    };
  };
}
