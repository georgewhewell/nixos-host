{ config, pkgs, ... }:

{

  systemd.tmpfiles.rules = let
    valetudo-map-card = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/TheLastProject/lovelace-valetudo-map-card/master/valetudo-map-card.js";
      sha256 = "0xsbzq0s982ml2lmd0zl5w92743iwh0h5b2s3f7znbp28rd29305";
    };
  in [
    "d /var/lib/hass/www 0755 hass hass"
    "L /var/lib/hass/www/valetudo-map-card.js - - - - ${valetudo-map-card}"
  ];

  services.home-assistant.config = {

    automation = [
      /* Start vacuum when george is away */
      {
        alias = "Start ROBOROCK";
        trigger = {
          platform = "time";
          at = "08:00:00";
          /* entity_id = "person.george";
          from = "home";
          to = "not_home";
          for = "00:05:00"; */
        };
        condition = [];
        action = {
          service = "vacuum.start";
          data = {};
          entity_id = "vacuum.robot";
        };
        /* mode = "single"; */
      }
    ];
  };
}
