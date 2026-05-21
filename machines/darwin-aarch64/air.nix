{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./darwin-configuration.nix
  ];

  networking.hostName = "air";
  ids.gids.nixbld = 30000;

  sconfig.xmrig = {
    enable = true;
    package = pkgs.xmrig;
    rigId = "mba";
    httpApi.accessToken = "xmrig";
    inhibit.nixBuilds.enable = true;
    mqttSwitch.passwordFile = "/Users/grw/.config/xmrig/mosquitto-password";
  };
}
