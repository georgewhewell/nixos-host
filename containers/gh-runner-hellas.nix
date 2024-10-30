{ config, lib, pkgs, ... }:


{

  users.users."gh-runner-hellas" = {
    isSystemUser = true;
    group = "gh-runner-hellas";
    extraGroups = [ "docker" ];
  };
  users.groups."gh-runner-hellas" = { };

  nix.settings.trusted-users = [ "gh-runner-hellas" ];

  systemd.services."container@gh-runner-hellas".unitConfig = {
    ConditionPathExists = "/run/gh-runner-hellas-a.secret";
  };

  deployment.keys."gh-runner-hellas-a.secret" =
    {
      keyCommand = [ "pass" "gh-runner/hellas-ai-a" ];
      destDir = "/run";
      uploadAt = "pre-activation";
      permissions = "0777";
    };

  deployment.keys."gh-runner-hellas-b.secret" =
    {
      keyCommand = [ "pass" "gh-runner/hellas-ai-b" ];
      destDir = "/run";
      uploadAt = "pre-activation";
      permissions = "0777";
    };

  deployment.keys."gh-runner-hellas-c.secret" =
    {
      keyCommand = [ "pass" "gh-runner/hellas-ai-c" ];
      destDir = "/run";
      uploadAt = "pre-activation";
      permissions = "0777";
    };

  containers.gh-runner-hellas = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    bindMounts = {
      "/run/gh-runner-hellas-a.secret".hostPath = "/run/gh-runner-hellas-a.secret";
      "/run/gh-runner-hellas-b.secret".hostPath = "/run/gh-runner-hellas-b.secret";
      "/run/gh-runner-hellas-c.secret".hostPath = "/run/gh-runner-hellas-c.secret";
    };

    config =
      let
        user = "gh-runner-hellas";
        extraPackages = with pkgs; [ docker ];
      in
      {
        imports = [ ../profiles/container.nix ];

        virtualisation.docker.enable = true;

        users.users."gh-runner-hellas" = {
          isSystemUser = true;
          group = "gh-runner-hellas";
          extraGroups = [ "docker" ];
        };
        users.groups."gh-runner-hellas" = { };

        services.github-runners."hellas-a" = {
          enable = true;
          url = "https://github.com/hellas-ai";
          tokenFile = "/run/gh-runner-hellas-a.secret";
          inherit extraPackages user;
        };

        services.github-runners."hellas-b" = {
          enable = true;
          url = "https://github.com/hellas-ai";
          tokenFile = "/run/gh-runner-hellas-b.secret";
          inherit extraPackages user;
        };

        services.github-runners."hellas-c" = {
          enable = true;
          url = "https://github.com/hellas-ai";
          tokenFile = "/run/gh-runner-hellas-c.secret";
          inherit extraPackages user;
        };

        networking.hostName = "gh-runner-hellas";
      };
  };
}
