{ config, pkgs, ... }:
let
  myPkgs = import ./pkgs { inherit pkgs; };
in
{
  imports = [
    <home-manager/nix-darwin>
    ./system.nix
  ];

  users.users."georgewhewell" = {
    shell = pkgs.zsh;
  };

  home-manager.users."georgewhewell" = { ... }: {
    imports = [
      ../../home/common.nix
      ../../home/darwin.nix
    ];
  };

  # Used for backwards compatibility, please read the changelog before changing.
  system.stateVersion = 3;
  services.nix-daemon.enable = true;

  nix.nixPath =
    [
      "darwin-config=$HOME/.nixpkgs/darwin-configuration.nix"
      "darwin=$HOME/.nix-defexpr/channels/darwin"
      "$HOME/.nix-defexpr/channels"
    ];

  programs.zsh.enable = true;

  environment.shellAliases = rec {
    ll = "eza --long --header --git --git-ignore --sort=created";
    gsp = "git stash && git pull";
    gspp = "${gsp} && git stash pop";
    slugify = "iconv -t ascii//TRANSLIT | sed -E 's/[~\^]+//g' | sed -E 's/[^a-zA-Z0-9]+/-/g' | sed -E 's/^-+\|-+$//g' | tr A-Z a-z";
  };

  nix = {
    maxJobs = 4;
    buildCores = 0;
  };

}
