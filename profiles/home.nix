{ config, pkgs, ... }:

{
  # Config for machines on home network
  time.timeZone = "Europe/London";

  # Allow resolving by .local
  services.avahi = {
    enable = true;
    nssmdns = true;
    publish.enable = true;
    publish.addresses = true;
  };

  # Log to ELK
  services.journalbeat = {
    enable = false;
    extraConfig = ''
      journalbeat:
        seek_position: cursor
        cursor_seek_fallback: tail
        write_cursor_state: true
        cursor_flush_period: 5s
        clean_field_names: true
        convert_to_numbers: false
        move_metadata_to_field: journal
        default_type: journal

      setup.kibana:
        host: "localhost:5601"

      output.elasticsearch:
        enabled: true
        protocol: "https"
        hosts: [ "es.satanic.link:443" ]
        index: "controllers"
        template.enabled: false

      queue_size: 50000
      logging.level: error
      logging.to_files: false
    '';
  };

  # Collect metrics for prometheus
  services.prometheus = {
    nodeExporter = {
      enable = true;
      openFirewall = true;
      enabledCollectors = [ "systemd" ];
    };
  };

}
