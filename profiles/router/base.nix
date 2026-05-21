# Common router configuration shared between Linux and VPP routing stacks
{
  config,
  lib,
  pkgs,
  network,
  ...
}: {
  options.router = {
    lanInterface = lib.mkOption {
      type = lib.types.str;
      description = "LAN interface for services (dnsmasq, etc.) to bind to";
    };
  };

  config = {
  # Network identity
  networking = {
    useDHCP = false;
    enableIPv6 = true;
    useNetworkd = true;
    nftables.enable = true;
    domain = network.domains.lan;
  };

  # Performance tuning for high-speed routing
  boot.kernel.sysctl = {
    # Network buffers
    "net.core.rmem_default" = 1048576;
    "net.core.wmem_default" = 1048576;
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.core.netdev_max_backlog" = 50000;
    "net.core.netdev_budget" = 1000;
    "net.core.somaxconn" = 8192;

    # TCP tuning for 25Gbps routing
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.tcp_rmem" = "4096 1048576 134217728";
    "net.ipv4.tcp_wmem" = "4096 1048576 134217728";
    "net.ipv4.tcp_slow_start_after_idle" = 0;
    "net.ipv4.tcp_mtu_probing" = 1;
    "net.ipv4.tcp_fastopen" = 3;
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.ipv4.tcp_max_syn_backlog" = 8192;
    "net.ipv4.route.max_size" = 524288;

    # Conntrack for many torrent connections
    "net.netfilter.nf_conntrack_max" = 524288;
    "net.nf_conntrack_max" = 524288;
    "net.netfilter.nf_conntrack_tcp_timeout_established" = 600;
  };

  # Kernel modules for routing
  boot.kernelModules = [
    "tcp_bbr"
  ];
  };
}
