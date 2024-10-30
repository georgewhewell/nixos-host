{ config, lib, pkgs, boot, networking, containers, ... }:

{

  users.users."gh-runner-grw" = {
    isSystemUser = true;
    group = "gh-runner-grw";
    extraGroups = [ "docker" ];
  };
  users.groups."gh-runner-grw" = { };

  nix.settings.trusted-users = [ "gh-runner-grw" ];

  systemd.services."container@gh-runner-grw".unitConfig = {
    ConditionPathExists = "/run/gh-runner-georgewhewell-nixos-host.secret";
  };

  deployment.keys."gh-runner-georgewhewell-nixos-host.secret" =
    {
      keyCommand = [ "pass" "gh-runner/georgewhewell/nixos-host" ];
      destDir = "/run";
      uploadAt = "pre-activation";
      permissions = "0777";
    };

  containers.gh-runner-grw = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    bindMounts = {
      "/run/gh-runner-georgewhewell-nixos-host.secret" = {
        hostPath = "/run/gh-runner-georgewhewell-nixos-host.secret";
        isReadOnly = false;
      };
    };

    config = {
      imports = [ ../profiles/container.nix ];

      users.users."gh-runner-grw" = {
        isSystemUser = true;
        group = "gh-runner-grw";
        extraGroups = [ "docker" ];
      };
      users.groups."gh-runner-grw" = { };

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
