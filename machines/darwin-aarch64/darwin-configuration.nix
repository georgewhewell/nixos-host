{ config, pkgs, inputs, ... }:

{
  imports = [
    ./system.nix
    ../../services/buildfarm-executor.nix
  ];

  nixpkgs.config.allowUnfree = true;

  users.users."grw" = {
    shell = pkgs.zsh;
    home = "/Users/grw";
  };

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
    package = pkgs.postgresql_16;
  };

  launchd.user.agents.postgresql.serviceConfig = {
    StandardErrorPath = "/tmp/postgres.error.log";
    StandardOutPath = "/tmp/postgres.log";
  };

  # Used for backwards compatibility, please read the changelog before changing.
  system.stateVersion = 3;
  services.nix-daemon.enable = true;

  programs.zsh.enable = true;

  nix = {
    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ]; # Enables use of `nix-shell -p ...` etc
    registry.nixpkgs.flake = inputs.nixpkgs; # Make `nix shell` etc use pinned nixpkgs
    extraOptions = ''
      system = aarch64-darwin
      experimental-features = nix-command flakes
      extra-platforms = aarch64-darwin x86_64-darwin
    '';
    settings = {
      max-jobs = 4;
      build-cores = 0;
      trusted-users = [ "grw" ];
      auto-optimise-store = true;
    };
  };
}
