{
  config,
  lib,
  ...
}: {
  boot.tmp.useTmpfs = lib.mkDefault true;
  nix.settings.trusted-users = ["root" "grw"];
  # keep-outputs intentionally NOT set here: slaves only execute remote builds
  # and have no .drv roots to anchor outputs to — it just wastes disk.
  # Hosts that dispatch builds get it from services/buildfarm-executor.nix.

  users.extraUsers.root.openssh.authorizedKeys.keys =
    config.users.users.grw.openssh.authorizedKeys.keys;
}
