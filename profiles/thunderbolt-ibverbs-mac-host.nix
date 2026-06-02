{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  thunderboltIbverbs = inputs.nix-strix-halo.inputs.thunderbolt-ibverbs;
  thunderboltIbverbsPackages = thunderboltIbverbs.packages.${pkgs.stdenv.hostPlatform.system};

  thunderboltIbverbsOptions = lib.concatStringsSep " " [
    "profile=mac_compat"
    "tbnet=allow"
    "tbnet_identity=stock"
    "roce_netdev=thunderbolt0"
    "lanes=1"
    "bind_services=1"
    "allocate_rings=1"
    "start_rings=1"
    "enable_tunnels=1"
    "native_data=0"
    "apple_data=1"
    "register_verbs=1"
    "apple_tx_max_inflight_wr=1"
    "apple_tx_max_inflight_frames=2"
    "apple_rx_pending_bytes=16777216"
    "apple_rx_pending_slots=4096"
    "apple_rx_pending_total_bytes=67108864"
  ];

  thunderboltIbverbsModule = config.boot.kernelPackages.callPackage (
    {
      stdenv,
      lib,
      kernel,
    }:
      stdenv.mkDerivation {
        pname = "thunderbolt-ibverbs";
        version = "0.1.0";
        src = thunderboltIbverbs;
        nativeBuildInputs = kernel.moduleBuildDependencies;
        buildPhase = ''
          runHook preBuild
          make -C thunderbolt-ibverbs/kernel \
            KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
            KVER=${kernel.modDirVersion} \
            modules
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          install -D -m 0644 thunderbolt-ibverbs/kernel/thunderbolt_ibverbs.ko \
            $out/lib/modules/${kernel.modDirVersion}/extra/thunderbolt_ibverbs.ko
          runHook postInstall
        '';
        dontPatchELF = true;
        dontStrip = true;
        dontFixup = true;
        meta = with lib; {
          description = "Thunderbolt IB verbs module";
          platforms = platforms.linux;
        };
      }
  ) {};

  thunderboltIbverbsReloadSystem = pkgs.writeShellApplication {
    name = "thunderbolt-ibverbs-reload-system";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      iproute2
      kmod
    ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "thunderbolt-ibverbs-reload-system: run this helper with sudo" >&2
        exit 1
      fi

      module="${thunderboltIbverbsModule}/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/extra/thunderbolt_ibverbs.ko"
      options="''${TBV_OPTIONS:-${thunderboltIbverbsOptions}}"
      wait_secs="''${TBV_WAIT_SECS:-8}"
      booted_module="/run/booted-system/kernel-modules/lib/modules/$(uname -r)/extra/thunderbolt_ibverbs.ko"

      if [ "''${TBV_ALLOW_NON_BOOTED_MODULE:-0}" != "1" ] &&
         [ -e "$booted_module" ] && ! cmp -s "$module" "$booted_module"; then
        echo "thunderbolt-ibverbs-reload-system: refusing to load thunderbolt_ibverbs from a non-booted system closure" >&2
        echo "  requested: $module" >&2
        echo "  booted:    $booted_module" >&2
        echo "reboot into the new generation first, or set TBV_ALLOW_NON_BOOTED_MODULE=1 for an ABI-compatible dev test" >&2
        exit 1
      fi

      if grep -q '^thunderbolt_ibverbs ' /proc/modules; then
        rmmod thunderbolt_ibverbs
      fi

      modprobe thunderbolt_net

      deps=$(modinfo -F depends "$module" | tr ',' ' ' || true)
      for dep in $deps; do
        [ -n "$dep" ] || continue
        modprobe "$dep"
      done
      modprobe ib_uverbs || true

      read -r -a opt_args <<< "$options"
      insmod "$module" "''${opt_args[@]}"

      if [ "$wait_secs" != "0" ]; then
        sleep "$wait_secs"
      fi
    '';
  };
in {
  boot.kernelModules = ["thunderbolt_net" "ib_uverbs"];

  environment.systemPackages = [
    thunderboltIbverbsModule
    thunderboltIbverbsReloadSystem
    thunderboltIbverbsPackages.rdma-core-usb4
    thunderboltIbverbsPackages.jaccl-examples
    thunderboltIbverbsPackages.uc-oneway
  ];

  systemd.services.thunderbolt-ibverbs-mac-host = {
    description = "Load Thunderbolt IB verbs in Mac compatibility mode";
    after = [
      "systemd-modules-load.service"
      "systemd-networkd.service"
    ];
    wants = ["systemd-networkd.service"];
    wantedBy = ["multi-user.target"];
    path = with pkgs; [
      coreutils
      gnugrep
      iproute2
      kmod
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      module="${thunderboltIbverbsModule}/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/extra/thunderbolt_ibverbs.ko"
      options="${thunderboltIbverbsOptions}"
      booted_module="/run/booted-system/kernel-modules/lib/modules/$(uname -r)/extra/thunderbolt_ibverbs.ko"

      if [ -e "$booted_module" ] && ! cmp -s "$module" "$booted_module"; then
        echo "thunderbolt-ibverbs-mac-host: refusing to load thunderbolt_ibverbs from a non-booted system closure" >&2
        echo "  requested: $module" >&2
        echo "  booted:    $booted_module" >&2
        echo "reboot into the new generation first" >&2
        exit 1
      fi

      if grep -q '^thunderbolt_ibverbs ' /proc/modules; then
        rmmod thunderbolt_ibverbs
      fi

      modprobe thunderbolt_net
      for _ in $(seq 1 20); do
        if ip link show thunderbolt0 >/dev/null 2>&1; then
          ip link set thunderbolt0 up || true
          break
        fi
        sleep 1
      done

      deps=$(modinfo -F depends "$module" | tr ',' ' ' || true)
      for dep in $deps; do
        [ -n "$dep" ] || continue
        modprobe "$dep"
      done
      modprobe ib_uverbs || true

      read -r -a opt_args <<< "$options"
      insmod "$module" "''${opt_args[@]}"
    '';
  };

  systemd.network.networks = {
    "20-thunderbolt0-mac-host" = {
      matchConfig.Name = "thunderbolt0";
      address = ["10.0.3.2/24"];
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "ipv6";
        MulticastDNS = "no";
        LLMNR = "no";
      };
      linkConfig.RequiredForOnline = "no";
    };
  };
}
