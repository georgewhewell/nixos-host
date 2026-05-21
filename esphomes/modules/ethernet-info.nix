{...}: {
  esphome.settings.text_sensor = [
    {
      platform = "ethernet_info";
      ip_address = {
        name = "IP Address";
        icon = "mdi:ip-network";
        entity_category = "diagnostic";
      };
      mac_address = {
        name = "MAC Address";
        icon = "mdi:chip";
        entity_category = "diagnostic";
      };
      dns_address = {
        name = "DNS Address";
        entity_category = "diagnostic";
      };
    }
  ];
}
