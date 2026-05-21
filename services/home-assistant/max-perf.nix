{...}: {
  services.home-assistant.config.automation = [
    {
      alias = "Publish Global Max Perf MQTT";
      mode = "single";
      trigger = [
        {
          platform = "homeassistant";
          event = "start";
        }
        {
          platform = "state";
          entity_id = "input_boolean.max_perf_all";
        }
      ];
      action = [
        {
          service = "mqtt.publish";
          data = {
            topic = "home/max_perf/all/set";
            payload = "{{ 'ON' if is_state('input_boolean.max_perf_all', 'on') else 'OFF' }}";
            retain = true;
            qos = 1;
          };
        }
      ];
    }
  ];
}
