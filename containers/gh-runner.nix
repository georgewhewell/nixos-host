{ config, lib, pkgs, boot, networking, containers, ... }:

{
  deployment.keys."gh-runner/georgewhewell/nixos-host.secret" =
    {
      keyCommand = [ "pass" "gh-runner/georgewhewell/nixos-host" ];
      destDir = "/run/keys";
      uploadAt = "pre-activation";
    };

  containers.gh-runner = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0.lan";

    bindMounts = {
      "/run/secrets/" = {
        hostPath = "/run/keys/gh-runner/georgewhewell/nixos-host.secret";
        isReadOnly = false;
      };
    };

    config = {
      imports = [ ../profiles/container.nix ];

      networking.hostName = "gh-runner";
    };

  };
}
