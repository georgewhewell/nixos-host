{ config, pkgs, ... }:

{
  imports = [
    ./system.nix
  ];

  users.users."grw" = {
    shell = pkgs.zsh;
    home = "/Users/grw";
  };

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

  nix = {
        package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    maxJobs = 4;
    buildCores = 0;
  };

}
