{ config, pkgs, ... }:

{
  # Config for machines on home network
  time.timeZone = "Europe/London";

  nix.binaryCaches = [
      https://cache.satanic.link
      https://cache.nixos.org
  ];
  nix.binaryCachePublicKeys = [
    "hydra.satanic.link-1:U4ZvldOwA3GWLmFTqdXwUu9oS0Qzh4+H/HSl8O6ew5o="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nixos-arm.dezgeg.me-1:xBaUKS3n17BZPKeyxL4JfbTqECsT+ysbDJz29kLFRW0=%"
  ];

  nix.distributedBuilds = true;
  nix.buildMachines = [
     {
      hostName = "localhost";
      maxJobs = "4";
      systems = [ "x86_64-linux" "i686-linux" ];
      supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
    }
    {
      hostName = "nixhost.lan";
      maxJobs = "12";
      systems = ["x86_64-linux" "i686-linux"];
      supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
    }
    {
      hostName = "gemini.lan";
      maxJobs = "4";
      systems = [ "aarch64-linux" ];
   }
  ];

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
  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = true;
      enabledCollectors = [ "systemd" ];
    };
  };

}
