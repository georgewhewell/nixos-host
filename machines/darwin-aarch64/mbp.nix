{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./darwin-configuration.nix
    ../../services/hydra-builder-slave-darwin.nix
  ];

  networking.hostName = "mbp";
  ids.gids.nixbld = 350;

  home-manager.users.grw = {...}: {
    imports = [
      inputs.hellas.homeManagerModules.default
    ];

    programs.hellas = {
      enable = true;
      serve.enable = true;
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
