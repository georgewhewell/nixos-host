# LicheeRV-Nano "RV Claw" (PicoClaw LCD unit) host-side serving.
#
# The claw hangs off this machine's USB port and follows the same
# diskless model as trex's strix netboot clients: USB supplies the stateless
# firmware/FIT handoff, then the board joins normal house WiFi and mounts
# trex's read-only Nix store. Whenever it enumerates in ROM download mode,
# udev starts
# claw-usb-boot.service, which pushes FIP -> fastboot -> FIT. The FIT's
# init= is the fleet `claw` nixosConfiguration's toplevel, so plugging
# the board always boots the latest deployed claw image; the initrd
# receives a SOPS-backed WiFi config over the private USB control link, then
# mounts /nix/store read-only from trex. Referencing the runner keeps the boot
# image on fuckup; trex separately GC-roots the complete target closure.
{ pkgs, inputs, config, mkSecret, ... }:
let
  protocol = import "${inputs.nanokvm}/lib/protocol.nix";
  cv181xRomPresence = import "${inputs.nanokvm}/lib/cv181x-rom-presence.nix";
  art = (import ../../../modules/nanokvm/fleet.nix { inherit inputs; }).artifacts pkgs;

  clawCfg = inputs.self.nixosConfigurations.claw;
  clawTargetIp = clawCfg.config.deployment.targetHost;
  # Link-local address derived from protocol.hostMac (02:1a:11:00:01:02).
  # Keep it static: this host disables automatic IPv6 link-local generation
  # for USB gadget interfaces, and the address must survive re-enumeration.
  clawHostLinkLocal = "fe80::1a:11ff:fe00:102";

  # Same composition as the nanokvm flake's nfsLiveArtifacts for the
  # picoclaw.mainline.live.usb-lcd catalog entry, but built from the
  # fleet claw configuration so init= points at the fleet toplevel.
  clawUsbTransport = art.mkNfsUsbBootRunner {
    name = "usb-boot";
    fit = art.mkBootFit {
      cfg = clawCfg;
      profile = "live";
      description = "SG2002 USB NFS live boot (claw, fleet)";
    };
    bootargs = art.mkLiveBootargs {
      cfg = clawCfg;
      # Nobody drains the ACM gadget console in this launcher flow, and
      # an undrained console=ttyGS0 backs up and wedges the kernel
      # mid-boot (why the catalog's usb-lcd-hs entry sets
      # artifactArgs.usbConsole = false). The kernel console stays on
      # ttyS0; use a picocom/ATTACH=shell manual run for console debug.
      usbConsole = false;
      # Mirror the usb-lcd catalog entry's artifactArgs.extraBootargs,
      # plus the picoclaw kernel-test's cpuidle A/B: this unit hit the
      # documented dwc2 RX stall ~12 min into its first stage 2 (usb0 RX
      # froze, the rx-guard's re-probe dropped the gadget for good and
      # the NFS root died with it). C906 WFI cpuidle is the suspect.
      extra = [
        "systemd.getty_auto=no"
        "udev.children_max=2"
        "cpuidle.off=1"
      ];
    };
    nfsServer = clawCfg.config.nanokvm.nfsLive.server;
    nfsExport = clawCfg.config.nanokvm.nfsLive.storeExport;
    waitForSsh = false;
  };

  # The upstream control-plane address is deliberately fixed to the USB
  # gadget subnet. For this WiFi-root profile, wait for the actual fleet SSH
  # endpoint after the USB handoff instead.
  clawUsbLive = pkgs.writeShellApplication {
    name = "usb-boot";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.netcat-openbsd
    ];
    text = ''
      ${cv181xRomPresence}

      work_root="''${RUNTIME_DIRECTORY:-/run/claw-usb-live}"
      install -d -m 0700 "$work_root"
      work_dir="$(mktemp -d --tmpdir="$work_root" wifi.XXXXXX)"
      wifi_conf="$work_dir/wpa_supplicant.conf"
      trap 'rm -f "$wifi_conf"; rmdir "$work_dir" 2>/dev/null || true' EXIT INT TERM

      ssid='Radio Free Europe'
      secret="$(tr -d '\r\n' < ${config.sops.secrets.wifi-password.path})"
      secret_bytes="$(printf '%s' "$secret" | wc -c)"
      if [ "$secret_bytes" -lt 8 ] || [ "$secret_bytes" -gt 63 ]; then
        echo "[usb-boot] invalid WiFi secret: WPA3-SAE requires an 8-63 byte passphrase" >&2
        exit 1
      fi
      escaped="$(printf '%s' "$secret" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
      sae_line="sae_password=\"$escaped\""
      unset escaped secret_bytes
      unset secret

      {
        printf 'ctrl_interface=/run/wpa_supplicant\n'
        printf 'update_config=0\n'
        printf 'country=CH\n'
        printf 'sae_pwe=2\n\n'
        printf 'network={\n'
        printf '  ssid="%s"\n' "$ssid"
        printf '  key_mgmt=SAE\n'
        printf '  ieee80211w=2\n'
        printf '  %s\n' "$sae_line"
        printf '  scan_ssid=1\n'
        printf '}\n'
      } > "$wifi_conf"
      unset sae_line
      chmod 0600 "$wifi_conf"

      ${clawUsbTransport}/bin/usb-boot "$@"

      echo "[usb-boot] sending WiFi config over the private USB link..."
      sent=0
      for _ in $(seq 1 240); do
        if nc -N -w 2 ${protocol.targetIp} ${toString protocol.ports.wifiConfig} \
            < "$wifi_conf" 2>/dev/null; then
          sent=1
          break
        fi
        sleep 0.5
      done
      if [ "$sent" != 1 ]; then
        echo "[usb-boot] Claw WiFi config receiver did not answer" >&2
        exit 1
      fi
      echo "[usb-boot] WiFi config accepted; waiting for Claw SSH on ${clawTargetIp}..."

      for _ in $(seq 1 240); do
        if timeout 1 ${pkgs.bash}/bin/bash -c \
            ':</dev/tcp/${clawTargetIp}/22' 2>/dev/null; then
          echo "[usb-boot] Claw SSH is up on ${clawTargetIp}"
          exit 0
        fi
        if cv181x_rom_present; then
          echo "[usb-boot] Claw returned to the CV181x BootROM; restarting the uploader" >&2
          exit 1
        fi
        sleep 1
      done

      echo "[usb-boot] Claw SSH did not answer on ${clawTargetIp}" >&2
      exit 1
    '';
  };
in
{
  sops.secrets.wifi-password = mkSecret "wifi-password" {
    mode = "0400";
  };

  # Expose the complete secret-injecting wrapper for focused builds/tests
  # without forcing evaluation of every workstation package on fuckup.
  system.build.clawUsbLive = clawUsbLive;

  # Win ahead of both profiles/thunderbolt-bridge.nix's generic 50-cdc-*
  # rules and the USB runner's compatibility 00-nanokvm-usb0 runtime file.
  # Networkd uses only the first matching .network file, so this rule owns
  # the whole control link across each gadget re-enumeration. Match the wire
  # protocol's host MAC so this covers both ECM/cdc_ether and CDC-NCM.
  systemd.network.networks."00-claw-usb" = {
    matchConfig.MACAddress = protocol.hostMac;
    address = [
      "${protocol.hostIp}/${protocol.prefix}"
      "${clawHostLinkLocal}/64"
    ];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
      IgnoreCarrierLoss = true;
    };
    linkConfig.RequiredForOnline = "no";
  };

  # Stable path for ad-hoc runs: /var/lib/claw-usb-live/bin/usb-boot
  # (NANOKVM_ATTACH=shell for an interactive bring-up session).
  systemd.tmpfiles.rules = [
    "L+ /var/lib/claw-usb-live - - - - ${clawUsbLive}"
  ];

  # The SG2002 ROM re-enumerates as this CVITEK download device on every
  # ~9 s USB-DL cycle, so a plugged-but-unbooted claw re-triggers the
  # rule until the service catches it; SYSTEMD_WANTS on an already-run
  # service is a no-op, so the ROM loop cannot stack instances.
  # ID_MM_DEVICE_IGNORE keeps ModemManager from probing the ROM's
  # CDC-ACM "USB Com Port" on every cycle.  Keep cdc_acm bound:
  # cv181x-rom-dl talks to the BootROM through the ttyACM device that
  # this driver creates.  Unbinding it removes the uploader's transport
  # and leaves every attempt stuck at "Connecting to ROM".
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="3346", ATTR{idProduct}=="1000", TAG+="systemd", ENV{SYSTEMD_WANTS}="claw-usb-boot.service", ENV{ID_MM_DEVICE_IGNORE}="1"
  '';

  systemd.services.claw-usb-boot = {
    description = "USB-boot the claw (LicheeRV-Nano PicoClaw) into its NFS live system";
    wantedBy = [ "multi-user.target" ];
    # udev-triggered only; starting it manually is fine too. A
    # successful pass (FIP pushed, FIT booted, SSH answered) exits 0 and
    # the board then keeps running off the kernel nfsd — nothing to
    # babysit. A give-up exits non-zero and re-arms the poller so the
    # next board reset is caught without manual intervention.
    serviceConfig = {
      Type = "simple";
      RuntimeDirectory = "claw-usb-live";
      RuntimeDirectoryMode = "0700";
      # This host's full-speed ROM path can spend ~25 seconds waiting for the
      # next enumeration and about 70 seconds draining the multi-stage FIP
      # transfer. The runner waits for 3346:1000 before opening an attempt's
      # 120-second transfer window, so an unattended wait cannot consume the
      # time needed by a real upload.
      ExecStart = "${clawUsbLive}/bin/usb-boot --rom-dl-verbose --rom-dl-timeout 900 --attempts 10";
      Environment = [
        "NANOKVM_ATTACH=none"
      ];
      Restart = "on-failure";
      RestartSec = "15s";
    };
  };
}
