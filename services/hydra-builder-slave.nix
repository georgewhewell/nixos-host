{config, lib, pkgs, ...}: let
  hydraBuilderShell = pkgs.writeShellScriptBin "hydra-builder-shell" ''
    export PATH=${config.nix.package}/bin:/run/current-system/sw/bin
    # Hydra already chose this host; do not forward its job through the
    # fleet's interactive builder list.
    export NIX_CONFIG="''${NIX_CONFIG:-}
    builders ="
    exec ${pkgs.bash}/bin/bash --noprofile --norc "$@"
  '';
in {
  users.users.hydra-builder = {
    isNormalUser = true;
    description = "Hydra remote builder";
    shell = "${hydraBuilderShell}/bin/hydra-builder-shell";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIdq150qf6Pybm5nHIYOHQXf1L/qZYbWrySYgLOJg3Md hydra-builder@ax102"
    ];
  };

  nix.settings.trusted-users = lib.mkAfter ["hydra-builder"];
}
