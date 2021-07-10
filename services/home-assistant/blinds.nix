{ config, pkgs, ... }:

{
  services.home-assistant.config = {
    sun = {};
    automation = [
      /* Open/Close blinds */
      {
        trigger = {
          platform = "numeric_state";
          entity_id = "sun.sun";
          value_template = "{{ state_attr('sun.sun', 'elevation') }}";
          below = -3.0;
        };
        action = [
          {
            service = "cover.close_cover";
            entity_id = "cover.main_blinds_2";
          }
          {
            service = "cover.close_cover";
            entity_id = "cover.side_blinds_2";
          }
        ];
      }
      {
        trigger = {
          platform = "numeric_state";
          entity_id = "sun.sun";
          value_template = "{{ state_attr('sun.sun', 'elevation') }}";
          above = -2.0;
        };
        action = [
          {
            service = "cover.open_cover";
            entity_id = "cover.main_blinds_2";
          }
          {
            service = "cover.open_cover";
            entity_id = "cover.side_blinds_2";
          }
        ];
      }
    ];
  };
}
