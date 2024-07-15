{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.sconfig.vpp-router;
  package = inputs.vifino.packages.${pkgs.system}.vpp;
  MB = 1024 * 1024;
in

{
  imports = [ inputs.vifino.nixosModules.vpp ];

  options.sconfig.vpp-router = {
    enable = lib.mkEnableOption "VPP router";
    trunk = lib.mkOption
      {
        type = lib.types.string;
        description = ''
          trunk interface
        '';
      };

    downstream = lib.mkOption
      {
        type = lib.types.listOf lib.types.string;
        default = [ ];
        description = ''
          downstream interfaces
        '';
      };

    dpdks = lib.mkOption
      {
        type = lib.types.listOf lib.types.string;
        default = [ ];
        description = ''
          pci ids to bind
        '';
      };

    inside_subnet = lib.mkOption
      {
        type = lib.types.int;
        default = 23;
        description = ''
          inside subnet
        '';
      };

    forwardedPorts = lib.mkOption
      {
        example = ''
          forwardedPorts = {
            "192.168.23.5" = [ 443 18080 ];
          };
        '';
        type = lib.types.attrsOf (lib.types.listOf lib.types.int);
        default = { };
        description = ''
          port forwards
        '';
      };

    netlinkBufferSize = lib.mkOption {
      type = lib.types.int;
      default = 64;
      description = ''
        Set the sysctl options for netlink buffer sizes (in Megabyte).
        Default (64MiB) should suffice for 1M routes.
      '';
    };
  };

  config =
    let
      bootstrap =
        let
          hostname = "gateway";
          inherit (cfg) trunk downstream inside_subnet;
          trunk_mac = "3c:ec:ef:d1:0e:f3";
          bvi_mac = "48:f8:b4:01:01:02";
        in
        ''
          # enable nat
          nat44 plugin enable sessions 63000

          # setup trunk ipv4
          set dhcp client intfc ${trunk} hostname gateway
          nat44 add interface address ${trunk}
          set interface nat44 out ${trunk} output-feature
          set interface state ${trunk} up

          # setup trunk ipv6
          set interface ip6 table ${trunk} 0
          ip6 nd address autoconfig ${trunk} default-route
          dhcp6 client ${trunk}
          dhcp6 pd client ${trunk} prefix group hgw

          # setup bridge
          bvi create instance 0
          set int state bvi0 up
          set int l2 bridge bvi0 1 bvi
          set int ip address bvi0 192.168.${toString inside_subnet}.1/24
          set interface nat44 in bvi0

          set ip6 address bvi0 prefix group hgw ::1/64
          ip6 nd address autoconfig bvi0 default-route
          ip6 nd bvi0 ra-managed-config-flag ra-other-config-flag ra-interval 5 3 ra-lifetime 180

          # tap
          create tap host-if-name lstack host-ip4-addr 192.168.${toString inside_subnet}.253/24 host-ip4-gw 192.168.${toString inside_subnet}.1
          set int l2 bridge tap0 1
          set int state tap0 up

          # port forwarding
          ${builtins.concatStringsSep "\n" (lib.flatten (lib.mapAttrsToList (ip: ports: map (port: ''
          nat44 add static mapping local ${ip} ${toString port} external ${trunk} ${toString port} tcp
          nat44 add static mapping local ${ip} ${toString port} external ${trunk} ${toString port} udp
          '') ports) cfg.forwardedPorts))}

          # setup ipv6 and nat
          ${builtins.concatStringsSep "\n" (map (port: ''
          set int l2 bridge ${port} 1
          set int state ${port} up
          enable ip6 interface ${port}
          ip6 nd address autoconfig ${port} default-route
          '') downstream)}
        '';
    in
    lib.mkIf cfg.enable {

      services.usbmuxd.enable = true;

      boot.initrd.kernelModules = [
        "nf_tables"
        "nft_compat"
        "i40e"
        "ice"
      ];

      boot.kernelModules = [
        "ipmi_devintf"
        "ipmi_si"
        "tcp_bbr"
        "vfio-pci"
      ];

      users.users.vpp = {
        group = "vpp";
        isSystemUser = true;
      };

      users.groups.vpp = { };

      environment.systemPackages = [
        package
        pkgs.pciutils
      ];

      boot.extraModulePackages = [
        config.boot.kernelPackages.dpdk-kmods
      ];

      networking = {
        useNetworkd = true;
        useDHCP = false;

        # No local firewall.
        nat.enable = false;
        firewall.enable = false;
      };

      networking.nameservers = [ "192.168.23.5" ];

      boot.kernelParams = [
        "intel_iommu=on"
        "amd_iommu=on"
        # "iommu=pt"
        "nosmt"
        "transparent_hugepage=never"
        "isolcpus=1-5" # vpp 1 main thread + 4 workers
        "nohz_full=1-5"
      ];

      boot.kernel.sysctl = {
        # ""
      };

      services.dnscrypt-proxy2 = {
        enable = true;
        settings = {
          listen_addresses = [ "127.0.0.1:54" ];
          static.cloudflare = {
            stamp = "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
          };
          # blacklist.blacklist_file = "${pkgs.sources.hosts-blocklists}/dnscrypt-proxy/dnscrypt-proxy.blacklist.txt";
        };
      };

      services.irqbalance.enable = lib.mkForce false;
      # nix
      # set num hugepages..
      services.vpp = {
        enable = cfg.enable;
        # package = package.overrideAttrs (o: {
        #   src = pkgs.fetchFromGitHub {
        #     owner = "FDio";
        #     repo = "vpp";
        #     rev = "v${version}";
        #     hash = "sha256-Cfm0Xzsx1UgUvIIeq5wBN6tA9ynCUa5bslEQk8wbd6E=";
        #   };
        # });
        uioDriver = "vfio-pci";
        inherit bootstrap;
        # statsegSize = 32;
        # mainHeapSize = 512;
        numberNumaNodes = 1;
        # buffersPerNuma = 8;

        workers = 4;
        pollSleepUsec = 10;
        # additionalHugePages = 512; #  ??
        extraConfig = ''
          dpdk {
            ${builtins.concatStringsSep "\n" (map (port: ''
            dev ${port}
            '') cfg.dpdks)}
          }
        '';
      };

      # restart automatically
      systemd.services.vpp.serviceConfig = {
        Restart = "always";
        RestartSec = "5";
      };

    };
}
