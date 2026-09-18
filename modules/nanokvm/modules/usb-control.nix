# Shared USB control plane for the NanoKVM USB-boot targets.
#
# Owns:
#   * networkd "40-usb0" matching the gadget MAC (initrd and stage-2)
#   * configureUsbNetwork — belt-and-suspenders address fixup
#   * acmStatus — one-shot initrd status block to /dev/ttyGS0
#   * debug shell on TCP/2323 (initrd BusyBox, stage-2 login shell)
#
# The kexec subsystem (request socket on TCP/2325, agent, payload mount,
# prepare-kexec-stage) used to live here too — now in
# ./control-plane/kexec.nix, imported via the `imports` list below.
{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.nanokvm.usbControl;

  # Shared helpers: protocol, kernel-dependent target tool list,
  # shellLib bash prelude, mkTargetScript builder.
  targetLib = import ./control-plane/target-script-lib.nix {
    inherit lib pkgs config;
  };
  inherit (targetLib) targetTools kernelIsMainline mkTargetScript protocol;

  configureUsbNetwork = mkTargetScript "nanokvm-configure-usb-network" ''
    log() {
      printf 'nanokvm-usb-network: %s\n' "$*" >/dev/kmsg 2>/dev/null || true
      printf '%s\n' "$*"
    }

    iface="$(nanokvm_wait_iface "$nanokvm_target_mac" 30)" || {
      log "no non-loopback network interface appeared"
      ip addr show || true
      exit 1
    }

    ip link set "$iface" up || true
    ip addr replace "$nanokvm_target_ip/$nanokvm_prefix" dev "$iface" || true
    ip addr show "$iface" || true
    log "configured $iface as $nanokvm_target_ip/$nanokvm_prefix"
  '';

  acmStatus = mkTargetScript "nanokvm-acm-status" ''
    for _ in $(seq 1 50); do
      [ -e /dev/ttyGS0 ] && break
      sleep 0.1
    done
    [ -e /dev/ttyGS0 ] || exit 0

    # Snapshot loop, 10 s apart, so the counters evolve across the
    # networkd/NFS-mount window. usb0 RX staying at 0 while the host
    # ARPs means the gadget's OUT path is dead; RX moving but TX stuck
    # means the IN path is.
    #
    # Output goes to /dev/kmsg, NOT /dev/ttyGS0: printk's ring buffer
    # is replayed to a console whenever it (re)registers, so these
    # lines survive ACM re-enumeration; direct ttyGS0 writes are
    # dropped whenever no host reader is attached at that instant.
    sleep 2
    mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
    # NOTE: no dyndbg here. Enabling dwc2/gadget debug prints while the
    # kernel console rides the same dwc2 gadget (ttyGS0) deadlocks the
    # console within seconds — printk recursion through the driver it's
    # logging. Keep this channel quiet.
    for i in 1 2 3 4 5 6; do
      {
        echo "===== snapshot $i ====="
        echo "--- netdev"; cat /proc/net/dev 2>&1 || true
        echo "--- udc-state"; for u in /sys/class/udc/*; do
              [ -e "$u" ] || continue
              printf '%s: %s\n' "''${u##*/}" "$(cat "$u/state" 2>/dev/null)"
            done
        echo "--- gadget-udc"; cat /sys/kernel/config/usb_gadget/sg2002/UDC 2>&1 || true
        echo "--- usb-devices"; cat /sys/kernel/debug/usb/devices 2>&1 || true
        echo "===== end snapshot $i ====="
      } 2>&1 | while IFS= read -r line; do
        printf 'nanokvm-status: %s\n' "$line" > /dev/kmsg
      done
      sleep 10
    done
  '';

  # The 40-usb0 networkd config, identical for initrd and stage-2.
  usbNetwork = {
    matchConfig = {
      MACAddress = protocol.targetMac;
    };
    address = [ "${protocol.targetIp}/${protocol.prefix}" ];
    networkConfig = {
      KeepConfiguration = "static";
      LinkLocalAddressing = "no";
    };
  };

  initrdDebugShellExec = "${pkgs.busybox}/bin/telnetd -F -b ${protocol.targetIp}:${toString protocol.ports.debugShell} -l ${pkgs.busybox}/bin/sh";
  stage2DebugShell = pkgs.writeShellScript "nanokvm-stage2-debug-shell" ''
    export PATH=/run/current-system/sw/bin:/run/wrappers/bin:$PATH
    export TERM="''${TERM:-linux}"
    user=${lib.escapeShellArg cfg.stage2ShellUser}
    cd / 2>/dev/null || true

    if getent passwd "$user" >/dev/null 2>&1 && [ -x /run/wrappers/bin/su ]; then
      exec /run/wrappers/bin/su -l "$user"
    fi

    if [ -x /run/wrappers/bin/su ]; then
      exec /run/wrappers/bin/su -l root
    fi

    root_shell="$(getent passwd root 2>/dev/null | cut -d: -f7 || true)"
    [ -n "$root_shell" ] || root_shell=/run/current-system/sw/bin/sh
    exec "$root_shell" -l
  '';
  stage2DebugShellExec = "${pkgs.busybox}/bin/telnetd -F -b ${protocol.targetIp}:${toString protocol.ports.debugShell} -l ${stage2DebugShell}";
in
{
  imports = [
    ./control-plane/inert-initrd.nix
    ./control-plane/kexec.nix
  ];

  options.nanokvm.usbControl = with lib; {
    initrd.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Expose the USB control plane (kexec, debug shell, networkd,
        ACM status) from the initrd. Pretty much every USB target
        wants this on; turn it off only for specialty configurations
        that bring up the gadget themselves.
      '';
    };

    stage2.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Expose the USB control plane (kexec, debug shell, networkd)
        from stage 2 as well. Required for kexec-out-of-stage-2;
        the corresponding initrd flag handles the initrd side.
      '';
    };

    stage2ShellUser = mkOption {
      type = types.str;
      default = "root";
      description = ''
        User account entered by the stage-2 TCP debug shell. The initrd
        debug shell remains BusyBox root because it runs before the
        NixOS account database exists.
      '';
    };

    kexec.enable = mkOption {
      type = types.bool;
      default = kernelIsMainline;
      description = ''
        Wire up the kexec control socket, request parser, and agent.

        Off by default on the vendor kernel because the target closure
        omits kexec-tools and nbd-client-minimal there (the vendor
        kernel-test path doesn't support kexec at all). Leaving the
        socket up on vendor systems creates a false-positive control
        plane: the parser ACKs the request, then the agent immediately
        fails to find the kexec binary.

        When false, the debug shell, networkd, and ACM status path stay
        as before — only the kexec endpoint disappears.
      '';
    };

    # `inertSwitchRoot.enable` option is defined in
    # ./control-plane/inert-initrd.nix.
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.initrd.enable {
      sg2002.usbGadget.network.enable = true;

      # USB-booted variants are loaded by U-Boot from a FIT and have no
      # disk to install a bootloader on. Suppress both bootloader paths
      # so eval doesn't insist on a target device.
      boot.loader.grub.enable = lib.mkForce false;
      boot.loader.generic-extlinux-compatible.enable = lib.mkForce false;

      boot.initrd.compressor = "zstd";
      boot.initrd.compressorArgs = [ "-19" "-T0" ];
      boot.initrd.network.enable = lib.mkForce false;
      boot.initrd.services.bcache.enable = lib.mkForce false;
      boot.initrd.services.lvm.enable = lib.mkForce false;
      boot.initrd.services.resolved.enable = lib.mkForce false;

      boot.initrd.systemd = {
        enable = true;
        emergencyAccess = false;

        dbus.enable = lib.mkForce false;
        fido2.enable = lib.mkForce false;
        tpm2.enable = lib.mkForce false;

        network = {
          enable = true;
          networks."40-usb0" = {
            matchConfig = lib.mkForce usbNetwork.matchConfig;
            address = lib.mkForce usbNetwork.address;
            inherit (usbNetwork) networkConfig;
          };
        };

        settings.Manager = {
          RebootWatchdogSec = "off";
          KExecWatchdogSec = "off";
          DefaultTimeoutStartSec = "infinity";
          DefaultTimeoutStopSec = "infinity";
          DefaultTimeoutAbortSec = "infinity";
          DefaultDeviceTimeoutSec = "infinity";
        };

        services = {
          "usb-debug-network" = {
            description = "Configure the USB debug network";
            wantedBy = [ "initrd.target" ];
            after = [ "usb-gadget.service" ];
            wants = [ "usb-gadget.service" ];
            unitConfig.DefaultDependencies = false;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = configureUsbNetwork;
            };
          };

          "usb-debug-shell" = {
            description = "Root shell on the USB debug network";
            wantedBy = [ "initrd.target" ];
            after = [
              "usb-debug-network.service"
              "systemd-networkd.service"
              "usb-gadget.service"
            ];
            wants = [
              "usb-debug-network.service"
              "systemd-networkd.service"
              "usb-gadget.service"
            ];
            unitConfig = {
              DefaultDependencies = false;
              # telnetd binds the static usb0 address; if it starts before
              # usb-debug-network has configured it, the bind fails and the
              # default start limit (5 in 10s) parks the unit FAILED
              # forever — which is exactly when you need the shell. Never
              # give up.
              StartLimitIntervalSec = 0;
            };
            serviceConfig = {
              ExecStart = initrdDebugShellExec;
              Restart = "always";
              RestartSec = "1s";
            };
          };

          "usb-debug-acm-status" = {
            description = "Print NanoKVM initrd status snapshots to kmsg";
            wantedBy = [ "initrd.target" ];
            after = [
              "usb-debug-network.service"
              "usb-gadget.service"
            ];
            wants = [
              "usb-debug-network.service"
              "usb-gadget.service"
            ];
            unitConfig.DefaultDependencies = false;
            serviceConfig = {
              # Long-running (the script loops internally): oneshot
              # would reap the loop with its cgroup on completion.
              ExecStart = acmStatus;
              Restart = "no";
            };
          };

          # Interactive root shell ON the ACM console would go here —
          # REMOVED: an sh exec'd with stdin on ttyGS0 sees instant
          # EOF whenever the host side has no writer attached and
          # crash-loops forever (observed: 600+ restarts in minutes,
          # churning the manager). The TCP debug shell on 2323 plus
          # the kmsg status snapshots are the debug channels.
        };

        # kexec socket + agent live in modules/control-plane/kexec.nix
        # (imported above). It contributes its own services/sockets/
        # storePaths under the same `boot.initrd.systemd` namespace.

        storePaths = [
          configureUsbNetwork
          acmStatus
          pkgs.busybox
        ];
      };
    })

    (lib.mkIf cfg.stage2.enable {
      # The independent keeper owns the nowayout watchdog across switch-root.
      systemd.settings.Manager = {
        RebootWatchdogSec = lib.mkDefault "off";
        KExecWatchdogSec = lib.mkDefault "off";
      };

      systemd.network = {
        enable = true;
        networks."40-usb0" = usbNetwork;
      };

      # Only allow the debug shell port on the USB iface. The kexec
      # module adds protocol.ports.kexecCtrl to the same list when it's
      # enabled.
      networking.firewall.interfaces.usb0.allowedTCPPorts = [
        protocol.ports.debugShell
      ];

      systemd.services."usb-debug-shell" = {
        description = "User shell on the USB debug network";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ]
          ++ lib.optional (config.services.userborn.enable && !config.services.userborn.static) "userborn.service";
        wants = [ "network-online.target" ]
          ++ lib.optional (config.services.userborn.enable && !config.services.userborn.static) "userborn.service";
        unitConfig = {
          # Same bind-race as the initrd shell: telnetd exits when the
          # static usb0 address is not configured yet, and the default
          # start limit would park the unit FAILED. Retry forever.
          StartLimitIntervalSec = 0;
        };
        serviceConfig = {
          ExecStart = stage2DebugShellExec;
          Restart = "always";
          RestartSec = "1s";
        };
      };
    })

    # Initrd-only test targets do not execute a remote stage-2 PID 1 and keep
    # systemd's normal watchdog ownership. The independent static keeper is
    # for the slow stage1-to-stage2 handoff where PID 1 can block on storage.
    (lib.mkIf (cfg.initrd.enable && cfg.stage2.enable) {
      sg2002.watchdogKeeper.initrd.enable = true;
      sg2002.watchdogKeeper.stage2.enable = true;
      sg2002.watchdogKeeper.healthHost = lib.mkDefault protocol.hostIp;
    })
  ];
}
