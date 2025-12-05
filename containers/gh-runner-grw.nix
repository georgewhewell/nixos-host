{
  config,
  lib,
  pkgs,
  boot,
  networking,
  containers,
  mkSecret,
  ...
}: {
  
  users.users."gh-runner-grw" = {
    isSystemUser = true;
    group = "gh-runner-grw";
    extraGroups = ["docker"];
  };
  users.groups."gh-runner-grw" = {};

  nix.settings.trusted-users = ["gh-runner-grw"];

  # Declare GitHub runner secret using sops-nix
  sops.secrets.gh-runner-grw = mkSecret "gh-runner-grw" {};

  containers.gh-runner-grw = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";
    localAddress = "192.168.23.50/24";

    bindMounts = {
      "/run/gh-runner-georgewhewell-nixos-host.secret" = {
        hostPath = "/run/gh-runner-georgewhewell-nixos-host.secret";
        isReadOnly = false;
      };
    };

    config = {
      imports = [../profiles/container.nix];

      users.users."gh-runner-grw" = {
        isSystemUser = true;
        group = "gh-runner-grw";
        extraGroups = ["docker"];
      };
      users.groups."gh-runner-grw" = {};

      services.github-runners."georgewhewell-nixos-host" = {
        enable = true;
        url = "https://github.com/georgewhewell/nixos-host";
        tokenFile = "/run/gh-runner-georgewhewell-nixos-host.secret";
        user = "gh-runner-grw";
        group = "gh-runner-grw";
      };

      networking.hostName = "gh-runner-georgewhewell-nixos-host";
    };
  };
}
