{ config, pkgs, ... }:

{
  imports = [
    ./system.nix
  ];

  nixpkgs.config.allowUnfree = true;

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
      ../../home/development.nix
      ../../home/darwin.nix
      ../../home/vscode.nix
    ];
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_14;
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
      system = aarch64-darwin
      experimental-features = nix-command flakes
      extra-platforms = aarch64-darwin x86_64-darwin 
    '';
    settings = {
      max-jobs = 4;
      build-cores = 0;
      trusted-users = [ "grw" ];
    };
  };
}
