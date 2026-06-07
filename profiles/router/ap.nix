{
  config,
  pkgs,
  lib,
  inputs,
  mkSecret,
  ...
}: let
  qcnPciPath =
    {
      rock-5b = "platform-a40000000.pcie-pci-0000:01:00.0";
    }
    .${config.networking.hostName} or "pci-0000:08:00.0";
in {
  sops.secrets.wifi-password = mkSecret "wifi-password" {};

  boot.kernelPackages = let
    openwrtAth12kPatches = [
      {
        name = "openwrt-cfg80211-dfs-available-grace-period";
        patch = ../patches/openwrt-cfg80211-dfs-available-grace-period.patch;
      }
      {
        name = "openwrt-cfg80211-concurrent-ap-on-dfs-with-sta";
        patch = ../patches/openwrt-cfg80211-concurrent-ap-on-dfs-with-sta.patch;
      }
      {
        name = "openwrt-ath12k-fix-5ghz-wideband-qcn9274";
        patch = ../patches/openwrt-ath12k-fix-5ghz-wideband-qcn9274.patch;
      }
    ];
    athKernel = pkgs.linuxKernel.kernels.linux_testing.override {
      kernelPatches =
        (pkgs.linuxKernel.kernels.linux_testing.kernelPatches or [])
        ++ openwrtAth12kPatches;
      argsOverride = {
        src = inputs.ath-kernel;
        version = "7.1-rc5";
        modDirVersion = "7.1.0-rc5";
      };
    };
  in
    lib.mkForce (pkgs.linuxPackagesFor athKernel);

  hardware.wirelessRegulatoryDatabase = true;

  hardware.enableAllFirmware = lib.mkForce false;
  hardware.enableRedistributableFirmware = lib.mkForce false;
  hardware.firmware = lib.mkForce (
    with pkgs;
      [
        qcn9274-fw-1_3_1-00217-mlo-dualmac-primary-vendor-board2-alias
        rock5b-minimal-firmware
        wireless-regdb
        ipw2200-firmware
        rtl8192su-firmware
        rt5677-firmware
        rtl8761b-firmware
        zd1211fw
        alsa-firmware
        sof-firmware
        libreelec-dvb-firmware
        broadcom-bt-firmware
        b43Firmware_5_1_138
        b43Firmware_6_30_163_46
        xone-dongle-firmware
      ]
      ++ lib.optional pkgs.stdenv.hostPlatform.isAarch raspberrypiWirelessFirmware
  );

  environment.systemPackages = with pkgs; [
    iw
    wirelesstools
  ];

  boot.extraModprobeConfig = ''
    # I don't think this works- wakiki seems to use its own regulatory domain, US
    options cfg80211 ieee80211_regdom="CH"
  '';

  systemd.network.links = {
    "10-wifi-wlan0" = {
      matchConfig = {
        Path = qcnPciPath;
        MACAddress = "00:03:7f:9b:9b:10";
      };
      linkConfig = {
        Name = "wlan0";
        NamePolicy = "";
      };
    };
  };

  # Remove systemd-networkd bridge config - hostapd will handle bridging
  systemd.network.networks."10-wifi-ap" = {
    matchConfig.Name = "wlan*";
    linkConfig.RequiredForOnline = "no";
    linkConfig.Unmanaged = "yes";
  };

  services.hostapd.enable = false;

  systemd.services.hostapd = {
    description = "IEEE 802.11 hostapd AP MLD";
    after = ["sys-subsystem-net-devices-wlan0.device"];
    bindsTo = ["sys-subsystem-net-devices-wlan0.device"];
    wantedBy = ["multi-user.target"];
    path = with pkgs; [
      coreutils
      hostapd
      iproute2
      iw
    ];
    preStart = ''
      set -euo pipefail

      password="$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.wifi-password.path})"

      rm -f /run/hostapd/*
      ${pkgs.coreutils}/bin/chgrp wheel /run/hostapd
      ${pkgs.coreutils}/bin/chmod 0750 /run/hostapd
      ${pkgs.iproute2}/bin/ip link set dev wlan0 down || true
      ${pkgs.iw}/bin/iw dev wlan0 set type managed || true
      ${pkgs.iproute2}/bin/ip link set dev wlan0 address 00:03:7f:9b:9b:10 || true

      cat > /run/hostapd/mld-5g.conf <<'EOF'
      # AP MLD link 0: 5 GHz, 80 MHz, non-DFS.
      # DFS/160 starts CAC with mld_ap=0, but fails start_dfs_cac() when this
      # link is part of an AP MLD on the current ath12k/mac80211 stack.
      interface=wlan0
      driver=nl80211
      ctrl_interface=/run/hostapd
      ctrl_interface_group=wheel
      bridge=br0.lan
      country_code=CH
      country3=0x49
      ieee80211d=1
      ieee80211h=1
      hw_mode=a
      channel=149
      ieee80211n=1
      ieee80211ac=1
      ieee80211ax=1
      ieee80211be=1
      ht_capab=[LDPC][HT40+][SHORT-GI-20][SHORT-GI-40][TX-STBC][RX-STBC1]
      vht_oper_chwidth=1
      vht_oper_centr_freq_seg0_idx=155
      vht_capab=[RXLDPC][RX-STBC-1][SHORT-GI-80][SHORT-GI-160][TX-STBC-2BY1][RX-ANTENNA-PATTERN][TX-ANTENNA-PATTERN][SU-BEAMFORMEE][MU-BEAMFORMEE][SU-BEAMFORMER][MU-BEAMFORMER]
      he_oper_chwidth=1
      he_oper_centr_freq_seg0_idx=155
      he_su_beamformer=1
      he_su_beamformee=1
      he_mu_beamformer=1
      eht_oper_chwidth=1
      eht_oper_centr_freq_seg0_idx=155
      eht_su_beamformer=1
      eht_su_beamformee=1
      eht_mu_beamformer=1
      mld_ap=1
      mld_addr=02:03:7f:9b:9b:00
      bssid=02:03:7f:9b:9b:10
      ssid=Radio Free Europe
      utf8_ssid=1
      wmm_enabled=1
      auth_algs=1
      wpa=2
      wpa_key_mgmt=SAE
      wpa_pairwise=CCMP
      rsn_pairwise=CCMP
      ieee80211w=2
      sae_require_mfp=1
      sae_pwe=2
      transition_disable=0x01
      EOF
      printf 'sae_password=%s\n' "$password" >> /run/hostapd/mld-5g.conf

      cat > /run/hostapd/mld-6g.conf <<'EOF'
      # AP MLD link 1: 6 GHz, 320 MHz, PSC channel 37.
      interface=wlan0
      driver=nl80211
      bridge=br0.lan
      country_code=CH
      country3=0x49
      ieee80211d=1
      ieee80211h=1
      hw_mode=a
      channel=37
      op_class=137
      ieee80211n=1
      ieee80211ac=1
      ieee80211ax=1
      ieee80211be=1
      ht_capab=[HT40][SHORT-GI-20][SHORT-GI-40]
      vht_oper_chwidth=0
      he_oper_chwidth=2
      he_oper_centr_freq_seg0_idx=47
      he_6ghz_reg_pwr_type=0
      he_su_beamformer=1
      he_su_beamformee=1
      he_mu_beamformer=1
      eht_oper_chwidth=9
      eht_oper_centr_freq_seg0_idx=31
      eht_su_beamformer=1
      eht_su_beamformee=1
      eht_mu_beamformer=1
      rnr=1
      unsol_bcast_probe_resp_interval=20
      mld_ap=1
      mld_addr=02:03:7f:9b:9b:00
      bssid=02:03:7f:9b:9b:11
      ssid=Radio Free Europe
      utf8_ssid=1
      wmm_enabled=1
      auth_algs=1
      wpa=2
      wpa_key_mgmt=SAE
      wpa_pairwise=CCMP
      rsn_pairwise=CCMP
      ieee80211w=2
      sae_require_mfp=1
      sae_pwe=2
      transition_disable=0x01
      EOF
      printf 'sae_password=%s\n' "$password" >> /run/hostapd/mld-6g.conf
    '';
    serviceConfig = {
      ExecStart = "${pkgs.hostapd}/bin/hostapd /run/hostapd/mld-5g.conf /run/hostapd/mld-6g.conf";
      ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      Restart = "always";
      RuntimeDirectory = "hostapd";
      RuntimeDirectoryMode = "0750";
      UMask = "0077";
      DeviceAllow = "/dev/rfkill rw";
      DevicePolicy = "closed";
      PrivateTmp = false;
    };
  };

  # hostapd Prometheus Exporter
  services.hostapd-exporter = {
    enable = true;
    interfaces = ["wlan0"];
    openFirewall = true;
  };
}
