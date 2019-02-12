{
  "router.lan" = (import ./router.nix);
  "nixhost.lan" = (import ./nixhost.nix);
  "fuckup.lan" = (import ./fuckup.nix);
  "yoga.lan" = (import ./yoga.nix);

  "hydra.lan" = (import ./containers/vms/hydra.nix);

}
