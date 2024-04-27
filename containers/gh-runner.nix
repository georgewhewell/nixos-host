{ config, lib, pkgs, boot, networking, containers, ... }:

{
  deployment.keys."gh-runner-georgewhewell-nixos-host.secret" =
    {
      keyCommand = [ "pass" "gh-runner/georgewhewell/nixos-host" ];
      destDir = "/run";
      uploadAt = "pre-activation";
      permissions = "0777";
    };

  containers.gh-runner = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0.lan";

    bindMounts = {
      "/run/gh-runner-georgewhewell-nixos-host.secret" = {
        hostPath = "/run/gh-runner-georgewhewell-nixos-host.secret";
        isReadOnly = false;
      };
    };

    config = {
      imports = [ ../profiles/container.nix ];

      services.github-runners."georgewhewell-nixos-host" = {
        enable = true;
        url = "https://github.com/georgewhewell/nixos-host";
        tokenFile = "/run/gh-runner-georgewhewell-nixos-host.secret";
      };

      networking.hostName = "gh-runner-georgewhewell-nixos-host";
    };

  };
}
