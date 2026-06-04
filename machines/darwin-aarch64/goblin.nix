{lib, ...}: {
  imports = [
    ./darwin-configuration.nix
    ../../profiles/darwin-no-power-management.nix
    ../../services/hydra-builder-slave-darwin.nix
  ];

  networking.hostName = "goblin";
  ids.gids.nixbld = 350;
  environment.enableAllTerminfo = lib.mkForce false;
}
