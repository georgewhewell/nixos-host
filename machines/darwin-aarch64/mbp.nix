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

  # Preserve the home created for this existing account by the original
  # nix-darwin generation; nix-darwin deliberately refuses to move user homes.
  users.users.hydra-builder.home = lib.mkForce "/private/var/empty_1";

  # macOS 27's enlarged dyld shared cache breaks the SBCL-backed mac-app-util:
  # the deployed runtime cannot start, and its replacement graph cannot yet
  # build in the local Nix sandbox. Keep this optional launcher integration off
  # on MBP; normal applications remain available under Nix Apps.
  services.mac-app-util.enable = false;

  home-manager.users.grw = {...}: {
    imports = [
      inputs.hellas.homeManagerModules.default
    ];

    targets.darwin.mac-app-util.enable = false;

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
