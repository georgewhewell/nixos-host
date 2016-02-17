{ config, lib, pkgs, ... }:

{
    services.collectd = {
      enable = true;
      extraConfig = ''
        # Interval at which to query values. Can be overwritten on per plugin
        # with the 'Interval' option.
        # WARNING: You should set this once and then never touch it again. If
        # you do, you will have to delete all your RRD files.
        Interval 10
        # Load plugins
        LoadPlugin apcups
        LoadPlugin contextswitch
        LoadPlugin cpu
        LoadPlugin df
        LoadPlugin disk
        LoadPlugin interface
        LoadPlugin irq
        LoadPlugin load
        LoadPlugin memory
        LoadPlugin network
        LoadPlugin processes
        LoadPlugin sensors
        LoadPlugin tcpconns
        LoadPlugin uptime
        LoadPlugin redis
        LoadPlugin nginx
        LoadPlugin postgresql

        # Ignore some paths/filesystems that cause "Permission denied" spamming
        # in the log and/or are uninteresting or duplicates.
        <Plugin "df">
          MountPoint "/var/lib/docker/*"
          MountPoint "/var/lib/docker"
          MountPoint "/var/lib/docker/zfs"
          MountPoint "/var/lib/docker/containers"
          MountPoint "/nix/store"  # it's just a bind mount, already covered
          FSType "fuse.gvfsd-fuse"
          FSType "cgroup"
          FSType "tmpfs"
          FSType "devtmpfs"
          IgnoreSelected true
        </Plugin>
        # Output/write plugin (need at least one, if metrics are to be persisted)
        <Plugin "network">
          Server "tsar.su" "25826"
        </Plugin>
      '';
    };
}
