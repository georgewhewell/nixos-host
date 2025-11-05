{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  boot.kernelPackages = let
    athKernel = pkgs.linuxKernel.kernels.linux_6_17.override {
      argsOverride = {
        src = inputs.ath-kernel;
        version = "6.17-rc7";
        modDirVersion = "6.17.0-rc7";
      };
    };
  in
    lib.mkForce (pkgs.linuxPackagesFor athKernel);

  hardware.wirelessRegulatoryDatabase = true;

  hardware.firmware = [
    pkgs.wakiki-fw # fw blobs i got from the vendor
    pkgs.ath12k-fw
  ];

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
        Path = "pci-0000:08:00.0";
        MACAddress = "00:03:7f:9b:9b:10";
      };
      linkConfig = {
        Name = "wlan0";
        NamePolicy = "";
      };
    };
    "10-wifi-wlan1" = {
      matchConfig = {
        Path = "pci-0000:08:00.0";
        MACAddress = "00:03:7f:9b:9b:11";
      };
      linkConfig = {
        Name = "wlan1";
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

  services.hostapd = let
    networkSettings = {
      ssid = "Radio Free Europe";
      authentication = {
        mode = "wpa3-sae-transition"; # WPA2+WPA3 for iwd compatibility
        saePasswordsFile = "/tmp/password";
        wpaPasswordFile = "/tmp/password";
      };
      settings = {
        bridge = "br0.lan";
      };
    };
    radioSettings = {
      country3 = "0x49"; # indoor
      acs_exclude_dfs = true;
      enable_background_radar = true;
      rnr = true;
      acs_num_scans = 20;
      # ocv = true;
      # dhcp_rapid_commit_proxy = true;
      # mld_ap = true;
    };
    wifiSettings = {
      wifi4 = {
        enable = true;
        capabilities = [
          "LDPC"
          "HT40+"
          # "HT40-" # errors on startup
          "SHORT-GI-20"
          "SHORT-GI-40"
          "TX-STBC"
          "RX-STBC1"
        ];
      };
      wifi5 = {
        enable = true;
        operatingChannelWidth = "80+80";
        capabilities = [
          "RXLDPC"
          "RX-STBC-1"
          "SHORT-GI-80"
          "SHORT-GI-160"
          "TX-STBC-2BY1"
          "RX-ANTENNA-PATTERN"
          "TX-ANTENNA-PATTERN"
          "SU-BEAMFORMEE"
          "MU-BEAMFORMEE"
          "SU-BEAMFORMER"
          "MU-BEAMFORMER"
        ];
      };
      wifi6 = {
        enable = true;
        operatingChannelWidth = "80+80";
        multiUserBeamformer = true;
        singleUserBeamformee = true;
        singleUserBeamformer = true;
      };
      wifi7 = {
        enable = true;
        operatingChannelWidth = "80";
        multiUserBeamformer = true;
        singleUserBeamformee = true;
        singleUserBeamformer = true;
      };
    };
  in {
    enable = true;
    radios = {
      # 5GHz radio (phy0) - needed for 6GHz discovery via RNR
      wlan0 = {
        band = "5g";
        countryCode = "CH";
        settings =
          radioSettings
          // {
            freqlist = "5180-5240";
          };
        networks.wlan0 = networkSettings;
        inherit (wifiSettings) wifi4 wifi5 wifi6 wifi7;
      };

      # 6GHz radio (phy1)
      wlan1 = {
        band = "6g";
        countryCode = "CH";
        settings =
          radioSettings
          // {
            freqlist = "5955-6415"; # matches ax210 in .lolch
            acs_exclude_6ghz_non_psc = true;
            # he_oper_centr_freq_seg0_idx = "47";
            he_6ghz_reg_pwr_type = "2"; # VLP- very low power
            punct_acs_threshold = "75";
            unsol_bcast_probe_resp_interval = "20";
          };
        networks.wlan1 = networkSettings;
        inherit (wifiSettings) wifi6 wifi7;
      };
    };
  };
}
