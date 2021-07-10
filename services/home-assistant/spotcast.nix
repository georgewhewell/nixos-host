{ config, pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    "C /var/lib/hass/custom_components/spotcast - - - - ${pkgs.sources.spotcast}/custom_components/spotcast"
    "Z /var/lib/hass 770 hass hass - -"
  ];

  services.home-assistant.config = {
    cast = {};
    spotcast = {
      "sp_dc" = pkgs.secrets.spotify-sp_dc;
      "sp_key" = pkgs.secrets.spotify-sp_key;
    };
    automation = [
      /* Start wake-up playlist */
      {
        trigger = {
          platform = "time";
          at = "07:05:00";
        };
        action = [
          {
            service = "spotcast.start";
            data = {
              spotify_device_id = "8ed23e57572077f6f5c112b63c0b6279";
              uri = "spotify:playlist:1QyZvdRFOEiCZykP43c9Ie";
              force_playback = true;
              random_song = true;
              shuffle = true;
              offset = 0;
              start_volume = 40;
              ignore_fully_played = true;
            };
          }
        ];
      }
    ];
  };

}
