{ config, lib, pkgs, network, ... }:
let
  host = network.hosts.${config.networking.hostName};
  useRdma = (host.netbootStorage or "rdma") == "rdma";
  storage = import ../machines/x86/trex/spdk-storage-constants.nix;
  volume = storage.netbootVolume config.networking.hostName;
  # O_DIRECT bypasses the client page cache. A cached executable or a ping
  # would continue passing when the network-backed store cannot perform I/O.
  probePath = if useRdma then
    "/dev/disk/by-id/nvme-uuid.${volume.uuid}"
  else
    "/nix/.ro-store/${baseNameOf config.systemd.package}/lib/systemd/systemd";
in
{
  # The normal-system watchdog did not cover a failed initrd storage mount.
  boot.initrd.kernelModules = [ "sp5100_tco" ];
  boot.initrd.systemd.settings.Manager = {
    RuntimeWatchdogSec = "60s";
    RebootWatchdogSec = "30s";
  };

  # PID 1 can still feed the hardware watchdog in emergency mode. Bound that
  # state explicitly, retaining a short interval for console diagnostics.
  boot.initrd.systemd.services.strix-initrd-recovery = {
    description = "Reboot after an unrecoverable Strix netboot failure";
    wantedBy = [ "emergency.target" ];
    unitConfig = {
      DefaultDependencies = false;
      FailureAction = "reboot-force";
    };
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "45s";
    };
    script = ''
      echo "Strix netboot entered emergency mode; rebooting in 30 seconds" > /dev/kmsg
      sleep 30
      systemctl --no-block --force reboot
    '';
  };

  # Includes the existing 30-minute closure-seeding allowance. Covers a boot
  # that remains activating without ever reaching emergency.target.
  boot.initrd.systemd.targets.initrd.unitConfig = {
    JobTimeoutSec = "35min";
    JobTimeoutAction = "reboot-force";
  };
  boot.initrd.systemd.services.strix-netboot-volume = lib.mkIf useRdma {
    unitConfig.FailureAction = "reboot-force";
  };
  boot.initrd.systemd.services.strix-netboot-seed = lib.mkIf useRdma {
    unitConfig.FailureAction = "reboot-force";
  };

  systemd.services.strix-storage-watchdog = {
    description = "Reboot if the Strix Nix store stops completing reads";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig = {
      RequiresMountsFor = [ "/nix/store" ];
      FailureAction = "reboot-force";
    };
    serviceConfig = {
      Type = "notify";
      NotifyAccess = "all";
      TimeoutStartSec = "120s";
      WatchdogSec = "120s";
      TimeoutAbortSec = "5s";
      TimeoutStopSec = "5s";
      LimitCORE = 0;
      Restart = "no";
    };
    path = [ pkgs.coreutils config.systemd.package ];
    script = ''
      set -eu
      # A blocked dd or executable page fault must not refresh the watchdog.
      # PID 1 owns the deadline independently of this service's blocked I/O.
      probe() {
        dd if=${lib.escapeShellArg probePath} of=/dev/null bs=4096 count=1 iflag=direct status=none
      }
      systemd-notify --ready
      while true; do
        if probe; then
          systemd-notify WATCHDOG=1
        else
          echo "Strix store read failed; waiting for watchdog deadline" >&2
        fi
        sleep 10
      done
    '';
  };
}
