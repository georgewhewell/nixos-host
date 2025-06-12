{
  pkgs,
  lib,
  ...
}: {
  /*
  asrock n100 itx board
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = false;
    };
  };

  system.stateVersion = "24.11";

  deployment.targetHost = "n100.satanic.link";
  deployment.targetUser = "grw";

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/headless.nix
    ../../../profiles/uefi-boot.nix
    # ../../../profiles/intel-gfx.nix  # Disabled - no graphics needed for headless server

    ../../../services/buildfarm-slave.nix
    ../../../services/home-assistant/default.nix
  ];

  hardware.firmwareCompression = "none";
  # hardware.enableAllFirmware = true;
  hardware.firmware = [
    pkgs.wakiki-fw
    # pkgs.ath12k-fw
  ];
  
  # Explicitly disable graphics since we removed intel-gfx.nix
  hardware.graphics.enable = lib.mkForce false;

  services.hostapd = {
    enable = true;
    radios = {
      wlan0 = {
        band = "5g";
        countryCode = "CH";
        channel = 149;
        # settings.he_oper_chwidth = 2;
        settings.country3 = "0x49"; # indoor
        # settings.op_class = 134; # 160 MHz channe
        # settings.ieee80211w = 2;
        # settings.sae_require_mfp = 1;
        # settings.vht_oper_centr_freq_seg0_idx = 155;
        wifi4.enable = true;
        wifi5 = {
          enable = true;
          operatingChannelWidth = "20or40";
          capabilities = [
            "RXLDPC"
            "RX-STBC-1"
            "SHORT-GI-80"
            "TX-STBC-2BY1"
            "SU-BEAMFORMEE"
            "MU-BEAMFORMEE"
            "SU-BEAMFORMER"
            "MU-BEAMFORMER"
          ];
        };
        wifi6 = {
          enable = true;
          operatingChannelWidth = "20or40";
          multiUserBeamformer = true;
          singleUserBeamformee = true;
          singleUserBeamformer = true;
        };
        wifi7 = {
          enable = false;
          operatingChannelWidth = "80";
          multiUserBeamformer = true;
          singleUserBeamformee = true;
          singleUserBeamformer = true;
        };

        networks = {
          wlan0 = {
            ssid = "Radio Free Europe";
            authentication = {
              mode = "wpa3-sae";
              saePasswordsFile = "/tmp/password";
            };
            # bssid = "36:b2:ff:ff:ff:ff";
            settings = {
              bridge = "br0.lan";
            };
          };
        };
      };
    };
  };

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = lib.mkForce true;
    };
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_testing;
    initrd.kernelModules = lib.mkForce [
      "bcachefs"
      "ixgbe"
      "r8169"
      "nfsv4"
    ];
    # Disable automatic hardware detection that adds usbhid
    initrd.systemd.enable = lib.mkForce false;
    initrd.availableKernelModules = lib.mkForce [
      "xhci_pci"
      "ehci_pci"
      "ata_piix"
      "nvme"
      "usb_storage"
      "bcachefs"
      "ixgbe" 
      "r8169"
    ];
    
    # ath12k patches from ath.git tree for hostapd/channel width fixes
    # 
    # Additional 2025 ath12k patch series available for testing:
    # 1. Real noise floor value (2 patches)
    #    Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=966986
    #    Submitter: Aditya Kumar Singh (May 28, 2025)
    # 
    # 2. Disable pdev for non supported country
    #    Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=967692
    #    Submitter: Muna Sinada (May 6, 2025)
    # 
    # 3. MU-MIMO and 160 MHz bandwidth support
    #    Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=968139
    #    Submitter: Pradeep Kumar Chitrapu (May 21, 2025)
    # 
    # 4. ⭐ REO queue lookup for QCN9274 hw2.0 (Your hardware!)
    #    Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=969123
    #    Submitter: Raj Kumar Bhagat (June 9, 2025)
    # 
    # 5. ⭐ Ring buffer corruption fix (Stability)
    #    Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=968952
    #    Submitter: Johan Hovold (June 4, 2025)
    # 
    # 6. MLO support
    #    Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=964845
    #    Submitter: Sarika Sharma (April 17, 2025)
    # 
    # 7. Monitor mode improvements
    #    Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=968796
    #    Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=968788
    # 
    # 8. Firmware crash handling
    #    Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=953786
    # 
    # 9. ⭐ Association improvements (Security/AP mode)
    #    Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=969590
    #    Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=967490
    # 
    # 10. Beacon protection
    #     Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=955243
    # 
    # 11. Mesh/Puncturing patterns
    #     Series: https://patchwork.kernel.org/project/linux-wireless/list/?series=969656
    
    kernelPatches = [
      {
        name = "ath12k-160mhz-center-freq-fix";
        patch = builtins.fetchurl {
          url = "https://git.kernel.org/pub/scm/linux/kernel/git/ath/ath.git/patch/?id=b1b01e46a3db5ad44d1e4691ba37c1e0832cd5cf";
          sha256 = "1z5fhk0qaa2qwyxdfd13dz2r1naa9cga89j1vsqy11p89wwrdqm1";
        };
      }
      # ⭐ REO queue lookup fix for QCN9274 hw2.0 - critical for your hardware
      {
        name = "ath12k-reoq-lut-qcn9274-hw2";
        patch = builtins.fetchurl {
          url = "https://patchwork.kernel.org/project/linux-wireless/patch/20250609-qcn9274-reoq-v1-1-a92c91abc9b9@quicinc.com/raw/";
          sha256 = "0rsfhmgjjnqlhpipbqrnr1yfhda7fjnqlpcq03qyyawbzh3kw88f";
        };
      }
      # Note: Ring buffer corruption fix series commented out due to conflicts with v6.15
      # These patches may already be partially applied or need rebasing
      # {
      #   name = "ath12k-ring-buffer-corruption-1-4";
      #   patch = builtins.fetchurl {
      #     url = "https://patchwork.kernel.org/project/linux-wireless/patch/20250604144509.28374-2-johan+linaro@kernel.org/raw/";
      #     sha256 = "1fc9xr564xmfirskbx329ghpyd2j07w2fnvb8s1zci00yrvi7klr";
      #   };
      # }
      # Note: Non-TX BSS association fix series commented out due to conflicts with v6.15
      # These patches are designed for newer kernel versions and fail to apply
      # {
      #   name = "ath12k-non-tx-bss-association-1-2";
      #   patch = builtins.fetchurl {
      #     url = "https://patchwork.kernel.org/project/linux-wireless/patch/20250530035615.3178480-2-rameshkumar.sundaram@oss.qualcomm.com/raw/";
      #     sha256 = "0klg08qw2cpcjhmsigr5342q40960y33xsnh2r0d54cqy1sd4flk";
      #   };
      # }
      # AP TPC power patch - conflicts with current kernel
      # {
      #   name = "ath12k-ap-tpc-power-cmd";
      #   patch = builtins.fetchurl {
      #     url = "https://patchwork.kernel.org/project/linux-wireless/patch/20250606112316.39316-1-quic_hbasuthk@quicinc.com/raw/";
      #     sha256 = "0i8cqhsp583ymc67m5ki35zqs0lb7xlv868w4lj9z6rsxmli0m3y";
      #   };
      # }
      # regdb fix already applied in kernel 6.15.1 (patch detected as reversed/applied)
      # {
      #   name = "ath12k-regdb-board-fix";
      #   patch = builtins.fetchurl {
      #     url = "https://raw.githubusercontent.com/openwrt/openwrt/main/package/kernel/mac80211/patches/ath12k/002-wifi-ath12k-Fetch-regdb.bin-file-from-board-2.bin.patch";
      #     sha256 = "1ji7c4pf2xpwx1la17390m3s7fp8y38yhbs27lnivscmygkzrbnn";
      #   };
      # }
      # EAPOL TX fix patch - conflicts with current kernel, comment out for now
      # {
      #   name = "ath12k-eapol-tx-fix";
      #   patch = builtins.fetchurl {
      #     url = "https://patchwork.kernel.org/project/linux-wireless/patch/20250530180247.424349-2-nithyanantham.paramasivam@oss.qualcomm.com/raw/";
      #     sha256 = "04w08qrllqh4ycdgr4r76n2n09qn31gxnmaxfprcx43v8cgl5zp0";
      #   };
      # }
      # Kernel size optimizations for n100 server
      {
        name = "n100-kernel-optimizations";
        patch = null;
        extraStructuredConfig = with lib.kernel; {
          # Minimal optimizations - only disable what we confirmed we don't need
          
          # Disable graphics entirely (no display hardware needed)
          DRM = lib.mkForce no;              # All GPU drivers including i915/xe
          FB = lib.mkForce no;               # Framebuffer support
          
          # Override specific graphics options that NixOS common config tries to set
          DRM_ACCEL = lib.mkForce unset;
          DRM_AMDGPU_CIK = lib.mkForce unset;
          DRM_AMDGPU_SI = lib.mkForce unset;
          DRM_AMDGPU_USERPTR = lib.mkForce unset;
          DRM_AMD_ACP = lib.mkForce unset;
          DRM_AMD_DC_FP = lib.mkForce unset;
          DRM_AMD_DC_SI = lib.mkForce unset;
          DRM_AMD_ISP = lib.mkForce unset;
          DRM_AMD_SECURE_DISPLAY = lib.mkForce unset;
          DRM_DISPLAY_DP_AUX_CEC = lib.mkForce unset;
          DRM_DISPLAY_DP_AUX_CHARDEV = lib.mkForce unset;
          DRM_FBDEV_EMULATION = lib.mkForce unset;
          DRM_GMA500 = lib.mkForce unset;
          DRM_HYPERV = lib.mkForce unset;
          DRM_I915_GVT = lib.mkForce unset;
          DRM_I915_GVT_KVMGT = lib.mkForce unset;
          DRM_LOAD_EDID_FIRMWARE = lib.mkForce unset;
          DRM_NOUVEAU_GSP_DEFAULT = lib.mkForce unset;
          DRM_NOUVEAU_SVM = lib.mkForce unset;
          DRM_PANIC = lib.mkForce unset;
          DRM_PANIC_SCREEN = lib.mkForce unset;
          DRM_PANIC_SCREEN_QR_CODE = lib.mkForce unset;
          DRM_SIMPLEDRM = lib.mkForce unset;
          HSA_AMD = lib.mkForce unset;
          MEDIA_CEC_RC = lib.mkForce unset;
          
          # Disable sound entirely (no audio hardware needed)  
          SOUND = lib.mkForce no;            # Sound drivers
          
          # Override specific sound options that NixOS common config tries to set
          SND_AC97_POWER_SAVE = lib.mkForce unset;
          SND_AC97_POWER_SAVE_DEFAULT = lib.mkForce unset;
          SND_DYNAMIC_MINORS = lib.mkForce unset;
          SND_HDA_CODEC_CS8409 = lib.mkForce unset;
          SND_HDA_INPUT_BEEP = lib.mkForce unset;
          SND_HDA_PATCH_LOADER = lib.mkForce unset;  
          SND_HDA_POWER_SAVE_DEFAULT = lib.mkForce unset;
          SND_HDA_RECONFIG = lib.mkForce unset;
          SND_OSSEMUL = lib.mkForce unset;
          SND_USB_CAIAQ_INPUT = lib.mkForce unset;
          SND_USB_AUDIO_MIDI_V2 = lib.mkForce unset;
          
          # Intel SOF sound options
          SND_SOC_INTEL_SOUNDWIRE_SOF_MACH = lib.mkForce unset;
          SND_SOC_INTEL_USER_FRIENDLY_LONG_NAMES = lib.mkForce unset;
          SND_SOC_SOF_ACPI = lib.mkForce unset;
          SND_SOC_SOF_APOLLOLAKE = lib.mkForce unset;
          SND_SOC_SOF_CANNONLAKE = lib.mkForce unset;
          SND_SOC_SOF_COFFEELAKE = lib.mkForce unset;
          SND_SOC_SOF_COMETLAKE = lib.mkForce unset;
          SND_SOC_SOF_ELKHARTLAKE = lib.mkForce unset;
          SND_SOC_SOF_GEMINILAKE = lib.mkForce unset;
          SND_SOC_SOF_HDA_AUDIO_CODEC = lib.mkForce unset;
          SND_SOC_SOF_HDA_LINK = lib.mkForce unset;
          SND_SOC_SOF_ICELAKE = lib.mkForce unset;
          SND_SOC_SOF_INTEL_TOPLEVEL = lib.mkForce unset;
          SND_SOC_SOF_JASPERLAKE = lib.mkForce unset;
          SND_SOC_SOF_MERRIFIELD = lib.mkForce unset;
          SND_SOC_SOF_PCI = lib.mkForce unset;
          SND_SOC_SOF_TIGERLAKE = lib.mkForce unset;
          SND_SOC_SOF_TOPLEVEL = lib.mkForce unset;
          
          # Disable major subsystems to speed up compilation
          KVM = lib.mkForce no;                  # Virtualization (huge compile time)
          BT = lib.mkForce no;                   # Bluetooth (not needed for server)
          INPUT = lib.mkForce no;                # Input devices (keyboard/mouse not needed for headless)
          VT = lib.mkForce no;                   # Virtual terminals (force off to allow INPUT disable)
          
          # Disable unused filesystems (keep bcachefs, nfs, ext4, fat, vfat)
          XFS_FS = lib.mkForce no;
          BTRFS_FS = lib.mkForce no; 
          JFS_FS = lib.mkForce no;
          
          # Disable wireless that we don't need (keep ath12k)
          CFG80211_WEXT = lib.mkForce no;        # Legacy wireless extensions
          
          # Disable advanced power management
          CPU_FREQ_GOV_ONDEMAND = lib.mkForce no;
          CPU_FREQ_GOV_CONSERVATIVE = lib.mkForce no;
          
          # Unset options for disabled subsystems
          FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER = lib.mkForce unset;
          FRAMEBUFFER_CONSOLE_DETECT_PRIMARY = lib.mkForce unset;
          FRAMEBUFFER_CONSOLE_ROTATION = lib.mkForce unset;
          KVM_AMD_SEV = lib.mkForce unset;
          KVM_ASYNC_PF = lib.mkForce unset;
          KVM_GENERIC_DIRTYLOG_READ_PROTECT = lib.mkForce unset;
          KVM_MMIO = lib.mkForce unset;
          KVM_VFIO = lib.mkForce unset;
          X86_SGX_KVM = lib.mkForce unset;
          LOGO = lib.mkForce unset;
          NVIDIA_SHIELD_FF = lib.mkForce unset;
          
          # Framebuffer specific options
          FB_3DFX_ACCEL = lib.mkForce unset;
          FB_ATY_CT = lib.mkForce unset;
          FB_ATY_GX = lib.mkForce unset;
          FB_EFI = lib.mkForce unset;
          FB_HYPERV = lib.mkForce unset;
          FB_NVIDIA_I2C = lib.mkForce unset;
          FB_RIVA_I2C = lib.mkForce unset;
          FB_SAVAGE_ACCEL = lib.mkForce unset;
          FB_SAVAGE_I2C = lib.mkForce unset;
          FB_SIS_300 = lib.mkForce unset;
          FB_SIS_315 = lib.mkForce unset;
          FB_VESA = lib.mkForce unset;
          FONTS = lib.mkForce unset;
          FONT_8x8 = lib.mkForce unset;
          FONT_TER16x32 = lib.mkForce unset;
          
          # Bluetooth specific options
          BT_HCIBTUSB_AUTOSUSPEND = lib.mkForce unset;
          BT_HCIBTUSB_MTK = lib.mkForce unset;
          BT_HCIUART = lib.mkForce unset;
          BT_HCIUART_QCA = lib.mkForce unset;
          BT_HCIUART_SERDEV = lib.mkForce unset;
          BT_QCA = lib.mkForce unset;
          
          # Input/HID specific options (now unused since INPUT disabled)
          HIDRAW = lib.mkForce unset;
          HID_ACRUX_FF = lib.mkForce unset;
          HID_BATTERY_STRENGTH = lib.mkForce unset;
          HID_BPF = lib.mkForce unset;
          HOLTEK_FF = lib.mkForce unset;
          INPUT_JOYSTICK = lib.mkForce unset;
          JOYSTICK_PSXPAD_SPI_FF = lib.mkForce unset;
          KEYBOARD_APPLESPI = lib.mkForce unset;
          LIRC = lib.mkForce unset;
          LOGIG940_FF = lib.mkForce unset;
          LOGIRUMBLEPAD2_FF = lib.mkForce unset;
          MOUSE_ELAN_I2C_SMBUS = lib.mkForce unset;
          MOUSE_PS2_ELANTECH = lib.mkForce unset;
          MOUSE_PS2_VMMOUSE = lib.mkForce unset;
          NINTENDO_FF = lib.mkForce unset;
          PLAYSTATION_FF = lib.mkForce unset;
          RC_CORE = lib.mkForce unset;
          SMARTJOYPLUS_FF = lib.mkForce unset;
          SONY_FF = lib.mkForce unset;
          THRUSTMASTER_FF = lib.mkForce unset;
          USB_HIDDEV = lib.mkForce unset;
          ZEROPLUS_FF = lib.mkForce unset;
          
          # More HID/input options
          CHROMEOS_TBMC = lib.mkForce unset;
          CROS_EC_ISHTP = lib.mkForce unset;
          DRAGONRISE_FF = lib.mkForce unset;
          GREENASIA_FF = lib.mkForce unset;
          
          # Fix the final errors - these are options for disabled subsystems
          FRAMEBUFFER_CONSOLE = lib.mkForce unset;    # FB is disabled, so this must be unset
          REISERFS_FS = lib.mkForce unset;           # We disabled this filesystem
          SND = lib.mkForce unset;                   # We disabled sound, so this must be unset
          BTRFS_FS_POSIX_ACL = lib.mkForce unset;    # Btrfs is disabled, so this must be unset
        };
      }
    ];
  };

  fileSystems."/" = {
    device = "UUID=8b8990d8-15a7-4308-a51c-4e5b7a6898e1";
    fsType = "bcachefs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2A3E-BFEC";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom="CH"
  '';

  environment.systemPackages = with pkgs; [
    wirelesstools
    iw
  ];

  networking = {
    hostName = "n100";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    useDHCP = false;

    wireless = {
      enable = false; # exclusive with iwd
      iwd = {
        enable = true;
        settings = {
          IPv6 = {
            Enabled = true;
          };
          # Settings = {
          #   AutoConnect = true;
          # };
        };
      };
    };
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    netdevs = {
      "20-br-lan" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br0.lan";
        };
      };
    };

    networks = {
      "10-lan" = {
        matchConfig.Driver = "r8169";
        networkConfig = {
          Bridge = "br0.lan";
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "enslaved";
      };
      "40-br" = {
        matchConfig.Name = "br0.lan";
        networkConfig = {
          IPv6AcceptRA = true;
        };
        address = [
          "192.168.23.14/24"
        ];
        routes = [
          {
            Gateway = "192.168.23.1";
            Metric = 1;
          }
        ];
      };
    };
  };
}
