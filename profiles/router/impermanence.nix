{ config, lib, ... }:
let
  persist = config.sconfig.impermanence.persistentStoragePath;

  persistentDirectories = [
    { directory = "/var/lib/dnsmasq"; user = "dnsmasq"; group = "root"; mode = "0755"; }
    # dnscrypt-proxy and go2rtc were here but moved to DynamicUser=true upstream.
    # State directory becomes /var/lib/private/<name>, which conflicts with a
    # persisted bind-mount at /var/lib/<name> (systemd can't rename a bind mount).
    # Neither service needs persistent state — caches are rebuilt — so ephemeral.
    { directory = "/var/lib/fail2ban"; mode = "0750"; }
    { directory = "/var/lib/frigate"; user = "frigate"; group = "frigate"; mode = "0750"; }
    { directory = "/var/cache/frigate"; user = "frigate"; group = "frigate"; mode = "0750"; }
    "/var/lib/fwupd"
    { directory = "/var/lib/hass"; user = "hass"; group = "hass"; mode = "0700"; }
    { directory = "/var/lib/mosquitto"; user = "mosquitto"; group = "mosquitto"; mode = "0700"; }
    "/var/lib/nftables"
    "/var/lib/systemd/linger"
    { directory = "/var/lib/tor"; user = "tor"; group = "tor"; mode = "0700"; }
    "/var/lib/unifi"
    "/var/lib/unifi-db"
  ];

  seedDirectories = map (entry:
    if lib.isString entry
    then entry
    else entry.directory
  ) persistentDirectories;
in
{
  sconfig.impermanence = {
    enable = true;
    # Reuse the current ZFS root dataset as persistent storage. Existing state
    # remains under /persist/<path>, and selected paths are bind-mounted back.
    persistentStoragePath = "/persist";
  };

  fileSystems."/" = lib.mkForce {
    device = "tmpfs";
    fsType = "tmpfs";
    neededForBoot = true;
    options = [
      "mode=755"
      "size=8G"
    ];
  };

  fileSystems."/persist" = {
    device = "zpool/root/nixos-router";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/nix" = {
    device = "/persist/nix";
    fsType = "none";
    options = [ "bind" ];
    depends = [ "/persist" ];
    neededForBoot = true;
  };

  environment.persistence.${persist}.directories = persistentDirectories;
  sconfig.impermanence.seedExisting.directories = seedDirectories;
}
