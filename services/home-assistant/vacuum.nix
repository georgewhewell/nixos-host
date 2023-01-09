{ config, pkgs, ... }:

{

  systemd.tmpfiles.rules =
    let
      valetudo-map-card = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/TheLastProject/lovelace-valetudo-map-card/master/valetudo-map-card.js";
        sha256 = "sha256-DMQK9v+u5DWzvxjpfFAYtLgHHYma9Ttes1Aw4lTJOa0=";
      };
    in
    [
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
          at = "12:00:00";
          /* entity_id = "person.george";
            from = "home";
            to = "not_home";
            for = "00:05:00"; */
        };
        condition = [ ];
        action = {
          service = "vacuum.start";
          data = { };
          entity_id = "vacuum.valetudo_roborock";
        };
        mode = "single";
      }
    ];
  };
}
