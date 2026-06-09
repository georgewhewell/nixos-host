{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./darwin-configuration.nix
    ../../profiles/darwin-no-power-management.nix
    ../../services/hydra-builder-slave-darwin.nix
  ];

  networking.hostName = "mbp";
  ids.gids.nixbld = 350;
  environment.enableAllTerminfo = lib.mkForce false;

  # mbp is a laptop; `pmset autorestart` (power.restartAfterPowerFailure, set by
  # darwin-no-power-management) isn't supported on portables and aborts activation.
  power.restartAfterPowerFailure = lib.mkForce null;

  home-manager.users.grw = {...}: {
    imports = [
      inputs.hellas.homeManagerModules.default
    ];

    programs.hellas = {
      enable = true;
      serve = {
        enable = true;
        port = 31145;
      };
    };
  };

  sconfig.xmrig = {
    enable = true;
    package = pkgs.xmrig;
    rigId = "mbp";
    httpApi.accessToken = "xmrig";
    inhibit.nixBuilds.enable = true;
    mqttSwitch.passwordFile = "/Users/grw/.config/xmrig/mosquitto-password";
  };
}
