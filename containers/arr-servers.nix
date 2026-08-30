{
  mkSecret,
  config,
  network,
  pkgs,
  ...
}: let
  self = network.hosts."arr-servers";
  qbittorrentPrepare = pkgs.writeShellScript "qbittorrent-prepare" ''
    set -eu
    profile=/var/lib/qbittorrent/qBittorrent/config
    config="$profile/qBittorrent.conf"

    ${pkgs.coreutils}/bin/rm -f "$profile/lockfile"

    # qB/libtorrent expects the complete IPv4 ToS / IPv6 traffic-class octet,
    # not the six-bit DSCP number. 32 is therefore CS1 (DSCP 8 shifted left
    # two bits), matching the switches' nixos-wan-bulk profile.
    if [ -e "$config" ]; then
      ${pkgs.crudini}/bin/crudini --set "$config" BitTorrent 'Session\PeerToS' 32
    fi
  '';
in {
  # Declare autobrr secret using sops-nix
  sops.secrets.autobrr = mkSecret "autobrr" {};

  systemd.services."container@arr-servers" = {
    bindsTo = ["mnt-Media.mount"];
    after = ["mnt-Media.mount"];
  };

  containers.arr-servers = {
    autoStart = true;
    privateNetwork = true;
    # Use SR-IOV VF instead of bridge for dedicated hardware NIC
    interfaces = ["mlxlan0v0"];

    bindMounts = {
      "/run/autobrr.secret".hostPath = "/run/autobrr.secret";
      "/var/lib/private/autobrr" = {
        hostPath = "/var/lib/autobrr";
        isReadOnly = false;
      };
      "/var/lib/radarr" = {
        hostPath = "/var/lib/radarr";
        isReadOnly = false;
      };
      "/var/lib/sonarr" = {
        hostPath = "/var/lib/sonarr";
        isReadOnly = false;
      };
      "/var/lib/qbittorrent" = {
        hostPath = "/var/lib/qbittorrent";
        isReadOnly = false;
      };
      "/mnt/Media" = {
        hostPath = "/mnt/Media";
        isReadOnly = false;
      };
      # 25G of library database and scraped metadata. Lives on trexroot and is
      # still covered by the host's impermanence persistence list.
      "/var/lib/jellyfin" = {
        hostPath = "/var/lib/jellyfin";
        isReadOnly = false;
      };
      # MUST be listed explicitly. nspawn resolves bind mounts at container
      # start and does NOT carry nested mounts, so binding the /var/lib/
      # qbittorrent parent alone would leave this an empty directory on the ZFS
      # dataset -- qBittorrent would write every partial torrent to the HDD
      # pool instead of the SPDK Optane volume, silently and with no error.
      "/var/lib/qbittorrent/incomplete" = {
        hostPath = "/var/lib/qbittorrent/incomplete";
        isReadOnly = false;
      };
      # qui's database: instance connections, settings, 78 migrations' worth of
      # schema. Missed on the first pass, and the failure was silent -- qui
      # simply created a fresh empty db inside the container rootfs and logged
      # "Applied 78 migrations successfully" as though all was well.
      "/var/lib/qui" = {
        hostPath = "/var/lib/qui";
        isReadOnly = false;
      };
      "/run/qui-session.secret".hostPath = "/run/qui-session.secret";
    };

    config = {
      imports = [../profiles/container.nix];

      system.stateVersion = "24.11";
      networking.hostName = "arr-servers";

      # Configure the SR-IOV VF interface (override DHCP from container.nix)
      networking.useNetworkd = true;
      networking.interfaces = {};  # Clear legacy interface config
      systemd.network = {
        enable = true;
        networks."10-vf" = {
          matchConfig.Name = "mlxlan0v0";
          address = [(network.cidrOf "lan" self.addresses.lan)];
          gateway = [network.routerIp];
          networkConfig = {
            DNS = network.routerIp;
          };
        };
      };

      # Media services moved off the host (2026-08-09) so everything media
      # shares one sandbox with its own address and firewall, reaching nothing
      # of trex's filesystem beyond the bindMounts above.
      #
      # These three UIDs/GIDs are PINNED to the host's allocations. radarr and
      # sonarr work across the boundary for free because nixpkgs gives them
      # static ids; jellyfin, qbittorrent and qui get *dynamically* allocated
      # ones, so the container would otherwise invent different numbers and be
      # unable to read its own bind-mounted state (/var/lib/jellyfin is uid 979
      # on disk, /var/lib/qbittorrent is uid 888). This container shares the
      # host's user namespace, so the numbers must agree exactly.
      users.users.jellyfin = { uid = 979; group = "jellyfin"; isSystemUser = true; };
      users.groups.jellyfin.gid = 975;
      users.users.qbittorrent = { uid = 888; group = "qbittorrent"; isSystemUser = true; home = "/var/lib/qbittorrent"; };
      users.groups.qbittorrent.gid = 888;
      users.users.qui = { uid = 968; group = "qui"; isSystemUser = true; };
      users.groups.qui.gid = 963;

      services.jellyfin = {
        enable = true;
        openFirewall = true;
      };
      # No /dev/dri passthrough: trex has only card0 (the ASPEED BMC
      # framebuffer) and no renderD128, so there is no render node and jellyfin
      # has always transcoded on CPU here. The old video/render group
      # membership on the host was aspirational.
      systemd.services.jellyfin = {
        unitConfig.RequiresMountsFor = ["/mnt/Media" "/var/lib/jellyfin"];
        serviceConfig.MemoryDenyWriteExecute = false;
      };

      services.qbittorrent = {
        enable = true;
        package = pkgs.qbittorrent-nox;
        profileDir = "/var/lib/qbittorrent";
        webuiPort = 8080;
        torrentingPort = 17026;
        openFirewall = true;
      };
      systemd.services.qbittorrent = {
        # An unclean container/host stop can leave Qt's single-instance lock in
        # the persistent profile. Its recycled PID then makes qBittorrent exit
        # successfully at boot, which bypasses Restart=on-failure.
        # The same preflight also enforces CS1 for peer traffic, so bulk flows
        # remain in the WAN scheduler's low-weight queue after a restore.
        serviceConfig.ExecStartPre = qbittorrentPrepare;
        unitConfig.RequiresMountsFor = [
          "/var/lib/qbittorrent"
          "/var/lib/qbittorrent/incomplete"
          "/mnt/Media"
        ];
      };

      services.qui = {
        enable = true;
        openFirewall = true;
        secretFile = "/run/qui-session.secret";
        settings = {
          host = "0.0.0.0";
          port = 7476;
        };
      };
      # qui is only a UI over qBittorrent's API; starting it first just makes
      # it show errors until qBittorrent is up.
      systemd.services.qui.after = ["qbittorrent.service"];

      users.users.radarr.extraGroups = ["qbittorrent"];
      users.users.sonarr.extraGroups = ["qbittorrent"];

      services.radarr = {
        enable = true;
        openFirewall = true;
      };

      services.sonarr = {
        enable = true;
        openFirewall = true;
      };

      services.autobrr = {
        enable = true;
        openFirewall = true;
        secretFile = "/run/autobrr.secret";
        settings = {
          host = "0.0.0.0";
          port = 7474;
        };
      };
    };
  };
}
