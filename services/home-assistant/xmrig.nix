{...}: {
  services.home-assistant.config.automation = [
    {
      alias = "Publish Global XMRig MQTT";
      mode = "single";
      trigger = [
        {
          platform = "homeassistant";
          event = "start";
        }
        {
          platform = "state";
          entity_id = "input_boolean.xmrig_all";
        }
      ];
      action = [
        {
          service = "mqtt.publish";
          data = {
            topic = "home/xmrig/all/set";
            payload = "{{ 'ON' if is_state('input_boolean.xmrig_all', 'on') else 'OFF' }}";
            retain = true;
            qos = 1;
          };
        }
      ];
    }
  ];
}
