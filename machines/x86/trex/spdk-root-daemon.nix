{
  config,
  lib,
  pkgs,
  ...
}: let
  spdk = pkgs.spdk-ublk;

  # Poll-mode reactors pinned to the top eight cores, 1 GiB of hugepages,
  # RPC socket on /run (which systemd carries across switch-root pre-mounted).
  cpuMask = "0xff00000000000000";
  mainCore = "56";
  rpcSocket = "/run/spdk/spdk.sock";

  # Dynamic member discovery: the 905P BDFs move around (PLX re-enumeration,
  # bifurcation resets), so bind by vendor:device and require exactly eight.
  # The patched spdk_tgt sets argv[0][0]='@' itself when /etc/initrd-release
  # exists (systemd ROOT_STORAGE_DAEMONS), so no exec -a wrapper is needed.
  startTarget = pkgs.writeShellApplication {
    name = "spdk-start-target";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      mapfile -t optane_bdfs < <(
        for device in /sys/bus/pci/devices/*; do
          if [ "$(cat "$device/vendor")" = 0x8086 ] \
            && [ "$(cat "$device/device")" = 0x2700 ]; then
            basename "$device"
          fi
        done | sort
      )
      [ "''${#optane_bdfs[@]}" -eq 8 ] || {
        echo "spdk: found ''${#optane_bdfs[@]} Optane 905P controllers (8086:2700), expected 8" >&2
        exit 1
      }
      for bdf in "''${optane_bdfs[@]}"; do
        set -- "$@" -A "$bdf"
      done
      exec ${spdk}/bin/spdk_tgt "$@"
    '';
  };

  daemonArgs = lib.concatStringsSep " " [
    "--wait-for-rpc"
    "-m ${cpuMask}"
    "-p ${mainCore}"
    "-s 6144"
    "--huge-dir /dev/hugepages1G"
    "-r ${rpcSocket}"
  ];

  # The survival contract from systemd.io/ROOT_STORAGE_DAEMONS, required on
  # BOTH sides of switch-root: PID 1 serializes the running unit across the
  # transition and the same-named stage-2 unit adopts it (plymouth pattern).
  survivalUnitConfig = {
    DefaultDependencies = false;
    IgnoreOnIsolate = true;
    RefuseManualStop = true;
    SurviveFinalKillSignal = true;
  };

  serviceConfig = {
    Type = "simple";
    ExecStart = "${startTarget}/bin/spdk-start-target ${daemonArgs}";
    LimitMEMLOCK = "infinity";
    RuntimeDirectory = "spdk";
    RuntimeDirectoryMode = "0750";
    # Never let systemd remove /run/spdk (and the RPC socket) out from
    # under the surviving daemon.
    RuntimeDirectoryPreserve = true;
    # A crashed target used to remain dead indefinitely while the successful
    # oneshot assembly/export units continued to advertise stale state. Restart
    # the empty --wait-for-rpc daemon; BindsTo edges in spdk-storage-stack.nix
    # tear down and then retry the stateful assembly/export transaction.
    Restart = "on-failure";
    RestartSec = "5s";
    TimeoutStartSec = "120s";
    OOMScoreAdjust = -1000;
  };

  environment = {
    # SPDK's OpenSSL init wants the baked openssl.cnf, absent in the initrd.
    OPENSSL_CONF = "/dev/null";
    # Patched SPDK honors TMPDIR for its CPU core lock files; /var/tmp does
    # not exist in the initrd.
    TMPDIR = "/run";
  };

  hugepageMount = {
    what = "hugetlbfs";
    where = "/dev/hugepages1G";
    type = "hugetlbfs";
    options = "pagesize=1G";
  };
in {
  # The 905Ps belong to SPDK: bind them to vfio-pci from the first moment so
  # the kernel nvme driver never claims them.
  boot.kernelParams = ["vfio-pci.ids=8086:2700"];
  boot.initrd.kernelModules = ["vfio_pci"];
  boot.initrd.systemd.storePaths = [
    spdk
    "${startTarget}/bin/spdk-start-target"
  ];

  boot.initrd.systemd.mounts = [
    (hugepageMount
      // {
        unitConfig.DefaultDependencies = false;
        wantedBy = ["initrd.target"];
      })
  ];
  systemd.mounts = [
    (hugepageMount
      // {
        unitConfig.DefaultDependencies = false;
        wantedBy = ["multi-user.target"];
      })
  ];

  # Stage 1: start the daemon. Phase 1 intentionally configures no bdevs and
  # mounts nothing — the daemon just comes up (--wait-for-rpc) and survives.
  boot.initrd.systemd.services.spdk-tgt = {
    description = "SPDK target (root storage daemon, initrd-resident)";
    wantedBy = ["initrd.target"];
    after = ["systemd-modules-load.service" "dev-hugepages1G.mount"];
    requires = ["dev-hugepages1G.mount"];
    unitConfig = survivalUnitConfig // {StartLimitIntervalSec = 0;};
    inherit environment serviceConfig;
  };

  # Stage 2: the identical twin. On switch-root the serialized running unit
  # is adopted under this definition; systemd never restarts the process.
  systemd.services.spdk-tgt = {
    description = "SPDK target (root storage daemon, initrd-resident)";
    wantedBy = ["multi-user.target"];
    after = ["dev-hugepages1G.mount"];
    unitConfig =
      survivalUnitConfig
      // {
        # If a future generation drops this unit, leave the daemon running.
        X-StopOnRemoval = false;
        StartLimitIntervalSec = 0;
      };
    inherit environment serviceConfig;
    # The canonical pairing (plymouth precedent): nixos-rebuild must never
    # stop/start/restart the adopted daemon. SPDK updates require an initrd
    # rebuild and a reboot, per the root-storage-daemon spec.
    restartIfChanged = false;
  };
}
