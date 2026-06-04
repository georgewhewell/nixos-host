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

  system.activationScripts.postActivation.text = lib.mkAfter ''
    if /usr/bin/id -u hydra-builder >/dev/null 2>&1 &&
       ! /usr/sbin/dseditgroup -o checkmember -m hydra-builder com.apple.access_ssh >/dev/null 2>&1; then
      /usr/sbin/dseditgroup -o edit -a hydra-builder -t user com.apple.access_ssh
    fi
  '';
}
