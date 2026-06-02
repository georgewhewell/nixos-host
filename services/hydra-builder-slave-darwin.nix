{ pkgs, lib, ... }: {
  users.knownUsers = [ "hydra-builder" ];
  users.users.hydra-builder = {
    uid = 700;
    gid = 20;
    description = "Hydra remote builder";
    home = "/var/empty";
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIdq150qf6Pybm5nHIYOHQXf1L/qZYbWrySYgLOJg3Md hydra-builder@ax102"
    ];
  };

  nix.settings.trusted-users = lib.mkAfter [ "hydra-builder" ];

  # macOS gates SSH login on com.apple.access_ssh group membership.
  # extraActivation runs as root after the `users` activation script creates the user.
  system.activationScripts.extraActivation.text = ''
    if /usr/bin/id -u hydra-builder >/dev/null 2>&1; then
      /usr/sbin/dseditgroup -o edit -a hydra-builder -t user com.apple.access_ssh \
        2>/dev/null || true
    fi
  '';
}
