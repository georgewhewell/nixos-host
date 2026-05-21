{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  cfg = config.hardware.mediatek-mt7927;

  repoSrc = inputs.mt7927.inputs.mediatek-mt7927-dkms;
  versions = builtins.fromJSON (builtins.readFile "${inputs.mt7927}/versions.json");

  # Parse PKGBUILD for ASUS firmware download info
  pkgbuild = builtins.readFile "${repoSrc}/PKGBUILD";
  driverFilename = let
    m = builtins.match ".*_driver_filename='([^']+)'.*" pkgbuild;
  in
    if m != null
    then builtins.head m
    else throw "mt7927: cannot parse driver filename from PKGBUILD";
  driverSha256Hex = let
    m = builtins.match ".*_driver_sha256='([a-f0-9]+)'.*" pkgbuild;
  in
    if m != null
    then builtins.head m
    else throw "mt7927: cannot parse driver sha256 from PKGBUILD";

  linuxDrivers = pkgs.fetchzip {
    url = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/snapshot/linux-${versions.mt76KVer}.tar.gz";
    hash = versions.mt76Hash;
  };

  asusZip = pkgs.fetchurl {
    url = "https://dlcdnets.asus.com/pub/ASUS/mb/08WIRELESS/${driverFilename}";
    hash = "sha256:${driverSha256Hex}";
    name = "asus-mt7927-driver.zip";
  };

  # Collect patches from the dkms repo, sorted by name for deterministic ordering
  repoFiles = builtins.attrNames (builtins.readDir repoSrc);

  wifiPatches = let
    patchFiles = builtins.filter (f:
      ((lib.hasPrefix "mt7927-wifi-" f) || (f == "mt7902-wifi-6.19.patch"))
      && (lib.hasSuffix ".patch" f))
    repoFiles;
  in
    map (f: "${repoSrc}/${f}") (builtins.sort builtins.lessThan patchFiles);

  btPatches = let
    patchFiles = builtins.filter (f:
      (lib.hasPrefix "mt6639-bt-" f) && (lib.hasSuffix ".patch" f))
    repoFiles;
  in
    map (f: "${repoSrc}/${f}") (builtins.sort builtins.lessThan patchFiles);

  mkMt7927 = kernel: let
    isClang = kernel.stdenv.cc.isClang or false;
    kernelBuild = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
    makeFlags =
      if isClang
      then "LLVM=1 CC=clang"
      else "";
  in {
    firmware = pkgs.stdenv.mkDerivation {
      pname = "mediatek-mt7927-firmware";
      version = "2.1";
      dontUnpack = true;
      nativeBuildInputs = [pkgs.libarchive pkgs.python3];
      buildPhase = ''
        runHook preBuild
        bsdtar -xf ${asusZip} mtkwlan.dat
        python3 ${repoSrc}/extract_firmware.py mtkwlan.dat firmware/
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        install -Dm644 firmware/BT_RAM_CODE_MT6639_2_1_hdr.bin \
          "$out/lib/firmware/mediatek/mt6639/BT_RAM_CODE_MT6639_2_1_hdr.bin"
        install -Dm644 firmware/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin \
          "$out/lib/firmware/mediatek/mt7927/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin"
        install -Dm644 firmware/WIFI_RAM_CODE_MT6639_2_1.bin \
          "$out/lib/firmware/mediatek/mt7927/WIFI_RAM_CODE_MT6639_2_1.bin"
        runHook postInstall
      '';
      meta.license = lib.licenses.unfreeRedistributableFirmware;
    };

    wifi = kernel.stdenv.mkDerivation {
      pname = "mediatek-mt7927-wifi";
      version = "2.1";
      src = "${linuxDrivers}/drivers/net/wireless/mediatek/mt76";
      nativeBuildInputs = kernel.moduleBuildDependencies ++ [pkgs.python3 pkgs.perl pkgs.kmod];
      patches = wifiPatches;
      buildPhase = ''
        runHook preBuild
        cat > Kbuild << 'KBUILD'
        obj-m += mt76.o
        obj-m += mt76-connac-lib.o
        obj-m += mt792x-lib.o
        obj-m += mt7921/
        obj-m += mt7925/
        mt76-y := mmio.o util.o trace.o dma.o mac80211.o debugfs.o eeprom.o tx.o agg-rx.o mcu.o wed.o scan.o channel.o pci.o
        mt76-connac-lib-y := mt76_connac_mcu.o mt76_connac_mac.o mt76_connac3_mac.o
        mt792x-lib-y := mt792x_core.o mt792x_mac.o mt792x_trace.o mt792x_debugfs.o mt792x_dma.o mt792x_acpi_sar.o
        CFLAGS_trace.o := -I$(src)
        CFLAGS_mt792x_trace.o := -I$(src)
        KBUILD

        cat > mt7921/Kbuild << 'KBUILD'
        obj-m += mt7921-common.o
        obj-m += mt7921e.o
        mt7921-common-y := mac.o mcu.o main.o init.o debugfs.o
        mt7921e-y := pci.o pci_mac.o pci_mcu.o
        KBUILD

        cat > mt7925/Kbuild << 'KBUILD'
        obj-m += mt7925-common.o
        obj-m += mt7925e.o
        mt7925-common-y := mac.o mcu.o regd.o main.o init.o debugfs.o
        mt7925e-y := pci.o pci_mac.o pci_mcu.o
        KBUILD
        make -C ${kernelBuild} M=$(pwd) ${makeFlags} modules
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        modDir="$out/lib/modules/${kernel.modDirVersion}/extra/mt76"
        install -dm755 "$modDir/mt7921" "$modDir/mt7925"
        install -m644 mt76.ko mt76-connac-lib.ko mt792x-lib.ko "$modDir/"
        install -m644 mt7921/*.ko "$modDir/mt7921/"
        install -m644 mt7925/*.ko "$modDir/mt7925/"
        runHook postInstall
      '';
    };

    bluetooth = kernel.stdenv.mkDerivation {
      pname = "mediatek-mt7927-bluetooth";
      version = "2.1";
      src = "${linuxDrivers}/drivers/bluetooth";
      nativeBuildInputs = kernel.moduleBuildDependencies ++ [pkgs.kmod];
      patches = btPatches;
      buildPhase = ''
        runHook preBuild
        echo "obj-m += btusb.o btmtk.o" > Makefile
        make -C ${kernelBuild} M=$(pwd) ${makeFlags} modules
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        modDir="$out/lib/modules/${kernel.modDirVersion}/extra/bluetooth"
        install -dm755 "$modDir"
        install -m644 btusb.ko btmtk.ko "$modDir/"
        runHook postInstall
      '';
    };
  };
in {
  options.hardware.mediatek-mt7927 = {
    enable = lib.mkEnableOption "MediaTek MT7927 / MT6639 WiFi and Bluetooth";
    enableWifi = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable MT7927 WiFi driver";
    };
    enableBluetooth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable MT7927 Bluetooth driver";
    };
    disableAspm = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Disable PCIe ASPM for MT7927 (fixes packet loss)";
    };
  };

  config = lib.mkIf cfg.enable (let
    builtModules = mkMt7927 config.boot.kernelPackages.kernel;
  in {
    hardware.firmware = [builtModules.firmware];
    boot.extraModulePackages =
      lib.optional cfg.enableWifi builtModules.wifi
      ++ lib.optional cfg.enableBluetooth builtModules.bluetooth;
    boot.kernelModules =
      lib.optionals cfg.enableWifi ["mt7925e" "mt7921e"]
      ++ lib.optionals cfg.enableBluetooth ["btmtk" "btusb"];
    services.udev.extraRules = lib.mkIf cfg.disableAspm ''
      ACTION=="add", SUBSYSTEM=="pci", \
        ATTR{vendor}=="0x14c3", ATTR{device}=="0x7927", \
        ATTR{link/l1_aspm}="0"
    '';
  });
}
