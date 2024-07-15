{ config, pkgs, lib, inputs, ... }:

{
  /*
    router: cwwk 8845hs board 
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = false;
    };
    wireguard = {
      enable = false;
    };
  };

  # systemd.services.create-vfs = {
  #   description = "Create VFs on Mellanox NIC";
  #   after = [ "network.target" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.bash}/bin/bash -c 'echo 2 > /sys/class/net/enp1s0f1np1/device/sriov_numvfs'";
  #     RemainAfterExit = true;
  #   };
  # };

  # systemd.services.set-multicast = {
  #   description = "Set multicast";
  #   after = [ "network.target" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.iproute}/bin/ip link set enp1s0f1np1 allmulticast on";
  #     RemainAfterExit = true;
  #   };
  # };

  environment.systemPackages = with pkgs; [
    btop
    wirelesstools
    bridge-utils
    ethtool
    tcpdump
    conntrack-tools
    pciutils
    iperf
  ];

  deployment.targetHost = "192.168.23.1";
  deployment.targetUser = "grw";

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/home.nix
      ../../../profiles/headless.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/router.nix
    ];

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelParams = [
    "amd_pstate=active"
    "pci=realloc=off"
  ];

  boot.initrd.kernelModules = [
    "nf_tables"
    "nft_compat"
    "igc"
    "mlx5_core"
  ];

  fileSystems."/" =
    {
      device = "zpool/root/nixos-router";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/5826-D605";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  services.dnsmasq =
    let
      lanBridge = "br0.lan";
    in
    {
      enable = true;
      servers = [ "127.0.0.1#54" ];
      extraConfig = ''
        domain-needed
        bogus-priv
        no-resolv
        no-hosts
        log-dhcp
        domain=lan.satanic.link
        local=/lan.satanic.link/
        bind-interfaces
        interface=${lanBridge}
        dhcp-range=${lanBridge},192.168.23.20,192.168.23.249,6h
        dhcp-option=${lanBridge},3,192.168.23.1    # send default gateway

        dhcp-host=e4:8d:8c:a8:de:40,192.168.23.2   # 10gb switch
        dhcp-host=80:2a:a8:80:96:ef,192.168.23.3   # ap
        dhcp-host=0c:c4:7a:89:fb:37,192.168.23.4   # x10 ipmi
        dhcp-host=0c:c4:7a:87:b9:d8,192.168.23.5   # nixhost
        dhcp-host=78:11:dc:ec:86:ea,192.168.23.6   # vacuum
        dhcp-host=06:f1:3e:03:27:8c,192.168.23.7   # fuckup
        dhcp-host=50:6b:4b:03:04:cb,192.168.23.8   # trex
        dhcp-host=48:A9:8A:93:42:4C,192.168.23.9   # 100gb switch
        dhcp-host=9c:6b:00:57:31:77,192.168.23.10  # trx90bmc
        dhcp-host=28:29:86:8b:3f:cb,192.168.23.11  # apc ups
        dhcp-host=b4:22:00:cf:18:63,192.168.23.12  # printer
        dhcp-host=c8:f0:9e:de:3c:2f,192.168.23.13  # cerberus

        # hosted names
        address=/router/192.168.23.254
        address=/nixhost/192.168.23.5
        address=/fuckup/192.168.23.7
        address=/trex/192.168.23.8
        address=/cloud/192.168.24.2
        address=/jellyfin/192.168.23.206
        address=/^satanic.link/192.168.23.1
        address=/grafana.satanic.link/192.168.23.5
        address=/home.satanic.link/192.168.23.5
        address=/jellyfin.satanic.link/192.168.23.5
        address=/paperless.satanic.link/192.168.23.5
        address=/radarr.satanic.link/192.168.23.5
        address=/sonarr.satanic.link/192.168.23.5
        address=/eth-mainnet.satanic.link/192.168.23.5
        address=/eth-mainnet-ws.satanic.link/192.168.23.5
        address=/hellas-mock-rpcserver.satanic.link/192.168.23.5
        address=/hellas-finetune-api.satanic.link/192.168.23.5
        address=/static.satanic.link/192.168.23.5
        address=/gateway.satanic.link/192.168.23.5
      '';
    };


  networking = {
    hostName = "router";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
  };
}
