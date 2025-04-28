{pkgs, ...}: {
  services.home-assistant = {
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      valetudo-map-card
    ];
    config = {
      automation = [
        /*
        Start vacuum when george is away
        */
        {
          alias = "Start ROBOROCK";
          trigger = {
            platform = "time";
            at = "12:00:00";
            /*
             entity_id = "person.george";
            from = "home";
            to = "not_home";
            for = "00:05:00";
            */
          };
          condition = [];
          action = {
            service = "vacuum.start";
            data = {};
            entity_id = "vacuum.valetudo_roborock";
          };
          mode = "single";
        }
      ];
    };
  };
}
