{
  inputs,
  ...
}: {
  imports = [
    ./darwin-configuration.nix
  ];

  ids.gids.nixbld = 30000;
}