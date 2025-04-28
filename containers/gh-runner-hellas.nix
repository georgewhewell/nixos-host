{pkgs, ...}: {
  users.users = {
    "gh-runner-hellas-a" = {
      isSystemUser = true;
      group = "gh-runner-hellas";
      extraGroups = ["docker"];
    };
    "gh-runner-hellas-b" = {
      isSystemUser = true;
      group = "gh-runner-hellas";
      extraGroups = ["docker"];
    };
    "gh-runner-hellas-c" = {
      isSystemUser = true;
      group = "gh-runner-hellas";
      extraGroups = ["docker"];
    };
  };
  users.groups."gh-runner-hellas" = {};

  nix.settings.trusted-users = [
    "gh-runner-hellas-a"
    "gh-runner-hellas-b"
    "gh-runner-hellas-c"
  ];

  systemd.services."container@gh-runner-hellas".unitConfig = {
    ConditionPathExists = "/run/gh-runner-hellas-a.secret";
  };

  deployment.keys."gh-runner-hellas-a.secret" = {
    keyCommand = ["pass" "gh-runner/hellas-ai-a"];
    destDir = "/run";
    uploadAt = "pre-activation";
    permissions = "0777";
  };

  deployment.keys."gh-runner-hellas-b.secret" = {
    keyCommand = ["pass" "gh-runner/hellas-ai-b"];
    destDir = "/run";
    uploadAt = "pre-activation";
    permissions = "0777";
  };

  deployment.keys."gh-runner-hellas-c.secret" = {
    keyCommand = ["pass" "gh-runner/hellas-ai-c"];
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

    config = let
      extraPackages = with pkgs; [docker];
    in {
      imports = [../profiles/container.nix];

      virtualisation.docker.enable = true;

      users.users = {
        "gh-runner-hellas-a" = {
          isSystemUser = true;
          group = "gh-runner-hellas";
          extraGroups = ["docker"];
        };
        "gh-runner-hellas-b" = {
          isSystemUser = true;
          group = "gh-runner-hellas";
          extraGroups = ["docker"];
        };
        "gh-runner-hellas-c" = {
          isSystemUser = true;
          group = "gh-runner-hellas";
          extraGroups = ["docker"];
        };
      };
      users.groups."gh-runner-hellas" = {};

      services.github-runners."hellas-a" = {
        enable = true;
        url = "https://github.com/hellas-ai";
        tokenFile = "/run/gh-runner-hellas-a.secret";
        user = "gh-runner-hellas-a";
        inherit extraPackages;
      };

      services.github-runners."hellas-b" = {
        enable = true;
        url = "https://github.com/hellas-ai";
        tokenFile = "/run/gh-runner-hellas-b.secret";
        user = "gh-runner-hellas-b";
        inherit extraPackages;
      };

      services.github-runners."hellas-c" = {
        enable = true;
        url = "https://github.com/hellas-ai";
        tokenFile = "/run/gh-runner-hellas-c.secret";
        user = "gh-runner-hellas-c";
        inherit extraPackages;
      };

      networking.hostName = "gh-runner-hellas";
    };
  };
}
