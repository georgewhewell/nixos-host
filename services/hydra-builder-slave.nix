{lib, ...}: {
  users.users.hydra-builder = {
    isNormalUser = true;
    description = "Hydra remote builder";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIdq150qf6Pybm5nHIYOHQXf1L/qZYbWrySYgLOJg3Md hydra-builder@ax102"
    ];
  };

  nix.settings.trusted-users = lib.mkAfter ["hydra-builder"];
}
