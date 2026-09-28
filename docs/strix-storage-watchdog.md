# Strix storage and boot recovery

The September 28 RDMA outage left the CPUs and PID 1 responsive while the
network-backed Nix stores stopped completing I/O. The normal 60-second hardware
watchdog could still be fed. A subsequent failed boot could remain indefinitely
in the initrd's locked emergency console: the initrd had neither a runtime
hardware watchdog nor a configured storage-failure reboot action.

`profiles/strix-storage-watchdog.nix`, imported by `netboot-client.nix`, adds:

- The SP5100 driver and a 60-second hardware watchdog in the initrd, with a
  30-second watchdog during reboot.
- Forced reboot after a failed private-volume connection or closure seed.
- Reboot after 30 seconds in initrd emergency mode, plus a 35-minute overall
  initrd job deadline accommodating the existing 30-minute seed timeout.
- A runtime service performing a direct 4 KiB read every 10 seconds. It probes
  the host's private namespace, or the NFS store in NFS boot mode. Successful
  reads refresh a 120-second service watchdog. Persistent errors, blocked I/O
  or a blocked probe process stop refreshing it and trigger `reboot-force`.

The probe bypasses the client's page cache. Ping, controller discovery and a
cached executable would not demonstrate that the store is still usable. PID 1
owns the service deadline; the blocked probe does not own its own timeout.
The existing normal-system hardware watchdog is the fallback if PID 1 itself
stops progressing. A reboot cannot repair a persistent switch fault, but the
host retries boot instead of requiring a reset after the fabric recovers.

## Verification

All four signed-image bundles built on trex. Inspection of Strix-2's actual
initrd verified the watchdog module, manager settings, emergency dependency,
storage failure action and overall job deadline. Direct probes passed against
the NFS store on Strix-1 and the private RDMA namespace on Strix-3.

Extract the evaluated service script and run the fault-injection test:

```sh
nix eval --raw .#nixosConfigurations.strix-2.config.systemd.services.strix-storage-watchdog.script > /tmp/strix-storage-probe.sh
python3 tests/strix-storage-watchdog.py /tmp/strix-storage-probe.sh
```

The test uses a temporary file, shortened deadlines and `FailureAction=none`.
It verifies recovery after a transient error and `Result=watchdog` after both
a persistent error and SIGSTOP of the whole probe service. All three passed
on trex. This tests detection without rebooting trex.

## September 29 deployment

The signed images are published on trex and signature-verified by the boot
router. Strix-2's router and origin payload hashes both equal
`88edfd9e26d5f82167f77c4507b19fe373d28cf07071ee7bd6289ec3f81c8dce`.
Strix-2 became reachable on its previous image while publication was finishing,
so its remaining reboot was performed through the real watchdog test below.

The runtime service is active with successful heartbeat updates on Strix-1,
3 and 4. Their initrd changes apply on their next boot. Strix-1 retains the
temporary NFS boot override used during storage recovery. Secure Boot keys,
kernel version and power policy are unchanged.

Strix-3 activation also exposed failure to unseal its existing TPM-bound host
credential and decrypt its MQTT secret. The sealed credential path is identical
in its old and new systems. SSH and the storage watchdog remain functional;
the identity/secret issue is separate from this recovery policy.

At 22:55:46 UTC, Strix-2's live probe service was deliberately stopped with
SIGSTOP. Its final heartbeat was 22:55:37. At 22:57:37 PID 1 logged a
120-second watchdog timeout, terminated the probe and marked it
`Result=watchdog`. The configured action rebooted the machine without a manual
reset. Router logs record fresh PXE/DHCP and retrieval of the new signed UKI
at 22:58:08–30. It returned to SSH with a new boot ID and system
`v4fm1y71j57i57yddlhw3ravh7amlggg-nixos-system-strix-2-26.11.20260916.b1b8759`.

Its new boot log records loading SP5100 at 2.3 seconds and starting the
60-second hardware watchdog in the initrd at 7.9 seconds. The watchdog
remained active through the switch to the normal system; the runtime
storage service resumed successful heartbeats. Nodes 1, 3 and 4 stayed up.
Logs are `watchdog-real-reboot-start.txt`, `watchdog-real-reboot-strix2.log`
and `watchdog-real-reboot-result.txt` under `/tmp/glm53-runtime`.

Build, signed-generation and rollback records are under
`/tmp/glm53-runtime/watchdog-deployments.json` on trex. Previous signed
generations are retained. The deployment is based on the existing signed-boot
work at `9e8b467`; the unrelated main checkout is not modified.

GitHub rejected pushing this branch because pre-existing ancestor commits
contain OAuth credentials in the quota exporter. No protection was bypassed.
The watchdog changes and their tests are committed locally.
