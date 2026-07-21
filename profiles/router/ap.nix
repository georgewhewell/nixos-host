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
    .${
      config.networking.hostName
    } or "pci-0000:08:00.0";

  # Building the generic ARM64 kernel natively on the Rock 5B takes roughly an
  # hour.  Keep the NixOS userspace native, but build this one target artifact
  # with the x86_64 -> aarch64 cross toolchain.  linuxPackagesFor below still
  # comes from the host package set, so out-of-tree modules and kernel tools do
  # not drag the complete cross-compiled system closure into the build.
  kernelBuildPkgs =
    if pkgs.stdenv.hostPlatform.system == "aarch64-linux"
    then
      import inputs.nixpkgs {
        localSystem = "x86_64-linux";
        crossSystem = "aarch64-linux";
      }
    else pkgs;
in {
  sops.secrets.wifi-password = mkSecret "wifi-password" {};
  # Shared 802.11r FT key holder secret. This must match the UniFi AC-Pro so
  # clients can fast-roam between rock-5b and the UniFi on VLAN 50.
  sops.secrets.wifi-ft-key = mkSecret "wifi-ft-key" {};

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

    # Gate whole Kconfig menus instead of maintaining lists of leaf drivers.
    # Rockchip is the only SoC family, RTL8125 and the Rockchip GMAC are the
    # only Ethernet paths, and ATH/Intel are the only WLAN vendor families.
    disabledArmPlatformGates = [
      "ARCH_ACTIONS"
      "ARCH_AIROHA"
      "ARCH_ALPINE"
      "ARCH_APPLE"
      "ARCH_AXIADO"
      "ARCH_BCM"
      "ARCH_BERLIN"
      "ARCH_BLAIZE"
      "ARCH_BST"
      "ARCH_CIX"
      "ARCH_EXYNOS"
      "ARCH_HISI"
      "ARCH_INTEL_SOCFPGA"
      "ARCH_K3"
      "ARCH_KEEMBAY"
      "ARCH_LG1K"
      "ARCH_MA35"
      "ARCH_MEDIATEK"
      "ARCH_MESON"
      "ARCH_MICROCHIP"
      "ARCH_MVEBU"
      "ARCH_NPCM"
      "ARCH_NXP"
      "ARCH_QCOM"
      "ARCH_REALTEK"
      "ARCH_RENESAS"
      "ARCH_SEATTLE"
      "ARCH_SOPHGO"
      "ARCH_SPRD"
      "ARCH_STM32"
      "ARCH_SUNXI"
      "ARCH_SYNQUACER"
      "ARCH_TEGRA"
      "ARCH_THUNDER"
      "ARCH_THUNDER2"
      "ARCH_UNIPHIER"
      "ARCH_VEXPRESS"
      "ARCH_VISCONTI"
      "ARCH_XGENE"
      "ARCH_ZYNQMP"
    ];
    disabledEthernetVendorGates = [
      "NET_VENDOR_3COM"
      "NET_VENDOR_ADAPTEC"
      "NET_VENDOR_ADI"
      "NET_VENDOR_AGERE"
      "NET_VENDOR_ALACRITECH"
      "NET_VENDOR_ALIBABA"
      "NET_VENDOR_AMAZON"
      "NET_VENDOR_AMD"
      "NET_VENDOR_AQUANTIA"
      "NET_VENDOR_ARC"
      "NET_VENDOR_ASIX"
      "NET_VENDOR_ATHEROS"
      "NET_VENDOR_BROADCOM"
      "NET_VENDOR_BROCADE"
      "NET_VENDOR_CADENCE"
      "NET_VENDOR_CAVIUM"
      "NET_VENDOR_CHELSIO"
      "NET_VENDOR_CISCO"
      "NET_VENDOR_CORTINA"
      "NET_VENDOR_DAVICOM"
      "NET_VENDOR_DEC"
      "NET_VENDOR_DLINK"
      "NET_VENDOR_EMULEX"
      "NET_VENDOR_ENGLEDER"
      "NET_VENDOR_EZCHIP"
      "NET_VENDOR_FUNGIBLE"
      "NET_VENDOR_GOOGLE"
      "NET_VENDOR_HISILICON"
      "NET_VENDOR_HUAWEI"
      "NET_VENDOR_INTEL"
      "NET_VENDOR_LITEX"
      "NET_VENDOR_MARVELL"
      "NET_VENDOR_MELLANOX"
      "NET_VENDOR_META"
      "NET_VENDOR_MICREL"
      "NET_VENDOR_MICROCHIP"
      "NET_VENDOR_MICROSEMI"
      "NET_VENDOR_MICROSOFT"
      "NET_VENDOR_MUCSE"
      "NET_VENDOR_MYRI"
      "NET_VENDOR_NATSEMI"
      "NET_VENDOR_NETRONOME"
      "NET_VENDOR_NI"
      "NET_VENDOR_NVIDIA"
      "NET_VENDOR_OKI"
      "NET_VENDOR_PENSANDO"
      "NET_VENDOR_QLOGIC"
      "NET_VENDOR_QUALCOMM"
      "NET_VENDOR_RDC"
      "NET_VENDOR_RENESAS"
      "NET_VENDOR_ROCKER"
      "NET_VENDOR_SAMSUNG"
      "NET_VENDOR_SEEQ"
      "NET_VENDOR_SILAN"
      "NET_VENDOR_SIS"
      "NET_VENDOR_SMSC"
      "NET_VENDOR_SOCIONEXT"
      "NET_VENDOR_SOLARFLARE"
      "NET_VENDOR_SUN"
      "NET_VENDOR_SYNOPSYS"
      "NET_VENDOR_TEHUTI"
      "NET_VENDOR_TI"
      "NET_VENDOR_VERTEXCOM"
      "NET_VENDOR_VIA"
      "NET_VENDOR_WANGXUN"
      "NET_VENDOR_WIZNET"
      "NET_VENDOR_XILINX"
      "NET_VENDOR_XIRCOM"
    ];
    disabledWlanVendorGates = [
      "WLAN_VENDOR_ADMTEK"
      "WLAN_VENDOR_ATMEL"
      "WLAN_VENDOR_BROADCOM"
      "WLAN_VENDOR_INTERSIL"
      "WLAN_VENDOR_MARVELL"
      "WLAN_VENDOR_MEDIATEK"
      "WLAN_VENDOR_MICROCHIP"
      "WLAN_VENDOR_PURELIFI"
      "WLAN_VENDOR_QUANTENNA"
      "WLAN_VENDOR_RALINK"
      "WLAN_VENDOR_REALTEK"
      "WLAN_VENDOR_RSI"
      "WLAN_VENDOR_SILABS"
      "WLAN_VENDOR_ST"
      "WLAN_VENDOR_TI"
      "WLAN_VENDOR_ZYDAS"
    ];
    # Nixpkgs common-config requests options below these parent gates.  Remove
    # those requests so the strict config checker can distinguish a deliberate
    # disabled subtree from a misspelled or unexpectedly unavailable option.
    disabledCommonConfigOptions = [
      "ACPI_APEI_PCIEAER"
      "AIC79XX_DEBUG_ENABLE"
      "AIC7XXX_DEBUG_ENABLE"
      "AIC94XX_DEBUG"
      "CEPH_FSCACHE"
      "CEPH_FS_POSIX_ACL"
      "CIFS_DFS_UPCALL"
      "CIFS_FSCACHE"
      "CIFS_UPCALL"
      "CIFS_XATTR"
      "DRM_AMDGPU_CIK"
      "DRM_AMDGPU_SI"
      "DRM_AMDGPU_USERPTR"
      "DRM_AMD_ACP"
      "DRM_AMD_DC_FP"
      "DRM_AMD_DC_SI"
      "DRM_AMD_ISP"
      "DRM_AMD_SECURE_DISPLAY"
      "DRM_NOUVEAU_SVM"
      "DRM_VC4_HDMI_CEC"
      "DVB_CORE"
      "EFI_VARS_PSTORE"
      "EROFS_FS_ZIP_DEFLATE"
      "EROFS_FS_ZIP_ZSTD"
      "F2FS_FS_COMPRESSION"
      "FSCACHE_STATS"
      "FSL_MC_UAPI_SUPPORT"
      "HSA_AMD"
      "HSA_AMD_P2P"
      "INFINIBAND_IPOIB"
      "INFINIBAND_IPOIB_CM"
      "JOYSTICK_PSXPAD_SPI_FF"
      "LIRC"
      "MEDIA_CEC_RC"
      "MEGARAID_NEWGEN"
      "MT798X_WMAC"
      "NET_VENDOR_MEDIATEK"
      "NFSD_V3_ACL"
      "NFSD_V4"
      "NFSD_V4_SECURITY_LABEL"
      "NFS_FS"
      "NFS_FSCACHE"
      "NFS_LOCALIO"
      "NFS_SWAP"
      "NFS_V3_ACL"
      "NFS_V4_2"
      "NFS_V4_SECURITY_LABEL"
      "NTFS3_FS_POSIX_ACL"
      "NTFS3_LZX_XPRESS"
      "PSTORE"
      "RT2800USB_RT53XX"
      "RT2800USB_RT55XX"
      "RTW88"
      "RTW88_8822BE"
      "RTW88_8822CE"
      "SCSI_LOWLEVEL_PCMCIA"
      "SND_FIREWIRE"
      "SND_HDA"
      "SND_HDA_CODEC_CS8409"
      "SND_HDA_INPUT_BEEP"
      "SND_HDA_PATCH_LOADER"
      "SND_HDA_POWER_SAVE_DEFAULT"
      "SND_HDA_RECONFIG"
      "SND_SOC_HDAC_HDA"
      "SQUASHFS_CHOICE_DECOMP_BY_MOUNT"
      "SQUASHFS_FILE_DIRECT"
      "SQUASHFS_LZ4"
      "SQUASHFS_LZO"
      "SQUASHFS_XATTR"
      "SQUASHFS_XZ"
      "SQUASHFS_ZLIB"
      "SQUASHFS_ZSTD"
      "SUN8I_DE2_CCU"
      "SUNRPC_DEBUG"
      "USB_DWC2_DUAL_ROLE"
      "USB_DWC3_DUAL_ROLE"
      "USB_XHCI_TEGRA"
      "U_SERIAL_CONSOLE"
    ];
    athKernel = kernelBuildPkgs.linuxKernel.kernels.linux_testing.override {
      # linux_testing inherits nixpkgs' generic ARM64 configuration, which is
      # deliberately suitable for almost every board.  This machine is not
      # generic: keep RK3588 plus its real PCI/USB devices and cut unrelated
      # SoCs and large driver families from the kernel build.
      structuredExtraConfig = with lib.kernel;
        {
          # Explicit keep-list anchors for rock's boot and actual hardware.
          ARCH_ROCKCHIP = lib.mkForce yes;
          ATH12K = lib.mkForce module;
          BTRFS_FS = lib.mkForce module;
          DRM_PANTHOR = lib.mkForce module;
          DRM_ROCKCHIP = lib.mkForce module;
          IWLWIFI = lib.mkForce module;
          R8169 = lib.mkForce module;
          SND_SOC = lib.mkForce module;
          SND_SOC_ES8316 = lib.mkForce module;
          SND_SOC_HDMI_CODEC = lib.mkForce module;
          SND_SOC_PCM5102A = lib.mkForce module;
          SND_SOC_ROCKCHIP_I2S = lib.mkForce module;
          SND_SOC_ROCKCHIP_I2S_TDM = lib.mkForce module;
          VFAT_FS = lib.mkForce yes;

          # Large subsystem or family gates with no matching hardware/use.
          ACPI_APEI = lib.mkForce no;
          ATM = lib.mkForce no;
          CAN = lib.mkForce no;
          DRM_AMDGPU = lib.mkForce no;
          DRM_NOUVEAU = lib.mkForce no;
          DRM_RADEON = lib.mkForce no;
          DRM_XE = lib.mkForce no;
          FDDI = lib.mkForce no;
          FIREWIRE = lib.mkForce no;
          IEEE802154 = lib.mkForce no;
          INFINIBAND = lib.mkForce no;
          INPUT_JOYSTICK = lib.mkForce no;
          INPUT_TOUCHSCREEN = lib.mkForce no;
          MEDIA_DIGITAL_TV_SUPPORT = lib.mkForce no;
          MISC_FILESYSTEMS = lib.mkForce no;
          NETWORK_FILESYSTEMS = lib.mkForce no;
          NFC = lib.mkForce no;
          RC_CORE = lib.mkForce no;
          SCSI_LOWLEVEL = lib.mkForce no;
          SND_HDA_ACPI = lib.mkForce no;
          SND_PCI = lib.mkForce no;
          SND_SOC_HDA = lib.mkForce no;
          USB_GADGET = lib.mkForce no;
          WAN = lib.mkForce no;
          XEN = lib.mkForce no;

          # Standalone local filesystems outside the two menus above.
          F2FS_FS = lib.mkForce no;
          GFS2_FS = lib.mkForce no;
          JFS_FS = lib.mkForce no;
          NTFS3_FS = lib.mkForce no;
          OCFS2_FS = lib.mkForce no;
          XFS_FS = lib.mkForce no;
        }
        // lib.genAttrs
        (disabledArmPlatformGates
          ++ disabledEthernetVendorGates
          ++ disabledWlanVendorGates)
        (_: lib.mkForce no)
        // lib.genAttrs disabledCommonConfigOptions (_: lib.mkForce unset);
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
      ftkey="$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets.wifi-ft-key.path})"

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
      # 802.11r Fast BSS Transition (FT-SAE), 802.11k RRM, and 802.11v BSS
      # transition. The mobility_domain and r0kh/r1kh key must match the UniFi.
      mobility_domain=5246
      ft_over_ds=0
      nas_identifier=rock5b5g
      reassociation_deadline=1000
      rrm_neighbor_report=1
      rrm_beacon_report=1
      bss_transition=1
      wnm_sleep_mode=1
      wpa=2
      wpa_key_mgmt=SAE FT-SAE
      wpa_pairwise=CCMP
      rsn_pairwise=CCMP
      ieee80211w=2
      sae_require_mfp=1
      sae_pwe=2
      transition_disable=0x01
      EOF
      printf 'sae_password=%s\n' "$password" >> /run/hostapd/mld-5g.conf
      printf 'r0kh=ff:ff:ff:ff:ff:ff * %s\n'                 "$ftkey" >> /run/hostapd/mld-5g.conf
      printf 'r1kh=00:00:00:00:00:00 00:00:00:00:00:00 %s\n' "$ftkey" >> /run/hostapd/mld-5g.conf

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
      # 802.11r Fast BSS Transition (FT-SAE), 802.11k RRM, and 802.11v BSS
      # transition. Same mobility_domain and FT key as the 5 GHz link.
      mobility_domain=5246
      ft_over_ds=0
      nas_identifier=rock5b6g
      reassociation_deadline=1000
      rrm_neighbor_report=1
      rrm_beacon_report=1
      bss_transition=1
      wnm_sleep_mode=1
      wpa=2
      wpa_key_mgmt=SAE FT-SAE
      wpa_pairwise=CCMP
      rsn_pairwise=CCMP
      ieee80211w=2
      sae_require_mfp=1
      sae_pwe=2
      transition_disable=0x01
      EOF
      printf 'sae_password=%s\n' "$password" >> /run/hostapd/mld-6g.conf
      printf 'r0kh=ff:ff:ff:ff:ff:ff * %s\n'                 "$ftkey" >> /run/hostapd/mld-6g.conf
      printf 'r1kh=00:00:00:00:00:00 00:00:00:00:00:00 %s\n' "$ftkey" >> /run/hostapd/mld-6g.conf
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
