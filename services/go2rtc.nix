{
  config,
  lib,
  pkgs,
  network,
  ...
}: let
  # Cameras exported to HomeKit. go2rtc derives device_id and device_private
  # deterministically from the stream name, so the only real state a paired
  # controller leaves behind is the `pairings` list.
  homekitStreams = [
    "esp32-s3-eth-01"
    "esp32-s3-eth-02"
    "esp32-p4-wifi"
    "esp32-p4-eth-01"
    "esp32-p4-eth-02"
  ];

  # go2rtc writes pairings back into its *first* -config argument (internal/
  # app/config.go: ConfigPath is the first file conf, and PatchConfig writes
  # there). The module's generated config lives in the Nix store and is
  # read-only, so that write silently fails and no pairing ever survives.
  # Hence: a writable config first, the declarative store config second.
  #
  # The two must not both declare `homekit`. Config files are unmarshalled in
  # order and a later file *replaces* a per-camera homekit struct wholesale
  # rather than merging into it — verified against go2rtc 1.9.14 — so a store
  # `homekit` block would wipe the pairings on every start. Streams do merge,
  # so those stay fully declarative below.
  stateConfig = "/var/lib/go2rtc/go2rtc.yaml";

  yaml = pkgs.formats.yaml {};
  storeConfig = yaml.generate "go2rtc.yaml" config.services.go2rtc.settings;

  # Empty maps are deliberate: go2rtc fills in its default PIN and the derived
  # device identity, and appends pairings here as controllers pair. `{}` (a map)
  # is required — a `[]` here is a YAML sequence and go2rtc rejects the whole
  # homekit block with an unmarshal error.
  homekitSeed = yaml.generate "go2rtc-homekit-seed.yaml" {homekit = {};};

  # Merge rather than seed-once. A plain "write the file if absent" is wrong:
  # every camera added to homekitStreams afterwards would silently never get a
  # HomeKit entry, because the file already exists. This adds only the missing
  # keys and leaves existing ones — crucially their `pairings` — untouched.
  seedScript = pkgs.writeShellScript "go2rtc-sync-homekit-state" ''
    set -eu
    if [ ! -e ${stateConfig} ]; then
      ${pkgs.coreutils}/bin/install -m 0644 ${homekitSeed} ${stateConfig}
    fi
    for stream in ${lib.escapeShellArgs homekitStreams}; do
      ${lib.getExe pkgs.yq-go} -i \
        "with(select(.homekit.\"$stream\" == null); .homekit.\"$stream\" = {})" \
        ${stateConfig}
    done
  '';
in {
  # go2rtc lives here rather than in services/frigate.nix so it can be deployed
  # on its own: it is what actually pulls MJPEG off the ESPHome cameras (:8080)
  # and re-serves it on :1984. Frigate is only one more consumer of these
  # streams, so it must not be a prerequisite for having cameras available.
  #
  # Note: go2rtc connects to a source lazily, on the first consumer request, so
  # a camera that is currently offline costs nothing here.
  services.go2rtc = {
    enable = true;
    settings.streams = {
      esp32-s3-eth-01 = [
        "http://${network.fqdn "esp32-s3-eth-01"}:8080"
      ];
      esp32-s3-eth-02 = [
        "http://${network.fqdn "esp32-s3-eth-02"}:8080"
      ];
      esp32-p4-wifi = [
        "http://${network.fqdn "esp32-p4-wifi"}:8080"
      ];
      esp32-p4-eth-01 = [
        "http://${network.fqdn "esp32-p4-eth-01"}:8080"
      ];
      esp32-p4-eth-02 = [
        "http://${network.fqdn "esp32-p4-eth-02"}:8080"
      ];
      rock-5b-hdmi = [
        "rtsp://${network.fqdn "rock-5b"}:8554/hdmi"
      ];
    };
  };

  # A static user rather than the module's DynamicUser: DynamicUser puts the
  # state under /var/lib/private/go2rtc behind a symlink, which is awkward to
  # bind-mount through impermanence. /var/lib/go2rtc is persisted alongside
  # hass and frigate in profiles/router/usb-btrfs.nix — without that, this
  # impermanent router would discard every HomeKit pairing on reboot.
  users.users.go2rtc = {
    isSystemUser = true;
    group = "go2rtc";
    home = "/var/lib/go2rtc";
  };
  users.groups.go2rtc = {};

  # go2rtc advertises its HomeKit accessories over mDNS on :1984 (the HAP port
  # is api.Port, not a separate one), and runs its own mDNS responder bound to
  # each interface — including the WiFi VLAN — so avahi reflection isn't needed
  # for it. But the port itself was closed on both LAN segments, so an iPhone
  # could discover the accessories and then fail to reach them. Apple's Home app
  # sends the mDNS hostname as the Host header, which is what lets go2rtc route
  # multiple cameras on this one port.
  networking.firewall.interfaces."br0.lan".allowedTCPPorts = [1984];
  networking.firewall.interfaces."br0.lan.50".allowedTCPPorts = [1984];

  systemd.services.go2rtc.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "go2rtc";
    Group = "go2rtc";
    ExecStartPre = seedScript;
    ExecStart = lib.mkForce "${config.services.go2rtc.package}/bin/go2rtc -config ${stateConfig} -config ${storeConfig}";
  };
}
