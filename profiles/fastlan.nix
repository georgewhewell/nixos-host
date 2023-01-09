{ config, pkgs, lib, ... }: 

{
    boot.kernel.sysctl = {
        
        "net.core.rmem_max" = 268435456;
        "net.core.wmem_max" = 268435456;

        "net.ipv4.conf.default.rp_filter" = 0;
        "net.ipv4.conf.all.rp_filter" = 0;

        "net.ipv4.conf.all.force_igmp_version" = 2;
        "net.ipv4.conf.default.force_igmp_version" = 2;

        "net.ipv4.neigh.default.gc_thresh3" = 4096;
        "net.ipv4.neigh.default.gc_thresh2" = 2048;
        "net.ipv4.neigh.default.gc_thresh1" = 1024;

        "net.ipv4.igmp_max_memberships" = 1024;
      };

      services.avahi = {
        enable = true;
        reflector = true;
      };
}