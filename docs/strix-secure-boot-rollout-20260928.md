# Strix Secure Boot rollout record — September 28, 2026

Historical enrollment evidence and incident notes. See the
[operating runbook](strix-secure-boot.md) for the current configuration.

## ConnectX boot diagnosis, September 28

The first observed initrd had only Realtek `eno1`, no RDMA device and no
bound mlx5 PCI function. A reboot restored both ConnectX-5 functions at
`c3:00.0` and `c3:00.1`. The cabled port is `cx5fabric0`, permanent MAC
`1c:34:da:61:12:b5`, operating at 100 Gbit/s over PCIe Gen3 x4. No fatal PCIe
error was observed; the initial disappearance remains unexplained.

A recovered boot exposed a second, concrete issue: applying RoCE pause/PFC
policy dropped the link just after network-online; `nvme connect` failed
with ECONNRESET before the link returned. `ctrl-loss-tmo` does not retry an
initial connection. The initrd now retries that connection up to 30 times,
with two-second delays, within the existing service timeout. Exhaustion
fails before formatting the private disposable boot volume.

The subsequent raw boot detected the card normally, connected at 17 seconds
on its first attempt, mounted `/nix` and `/models` over RDMA, and reached
stage 2 without intervention or failed services. This boot validated normal
operation with the new initrd; it did not reproduce the transient failure.
No LAN/NFS-root fallback was enabled.

## Canary deployment and hardware acceptance

On September 28, strix-1 booted the signed network UKI with `SecureBoot=1`
and `SetupMode=0`, including after a physical power cycle. The cold boot
reported the router URL in `bootctl status`; both ConnectX functions bound
to mlx5, `/nix` mounted read-write over RDMA and `/models` mounted read-only.
Comparing efivar backups confirmed PK, KEK and dbx were byte-for-byte
unchanged and all four original db entries remained alongside the fleet
certificate.

The router cache configuration is activated and selected for subsequent
boots. An origin-outage test returned HTTP 404 from Trex while the router
continued serving the previous, unchanged UKI; restoring the origin and
refreshing succeeded. Rock's recovery-image configuration is also activated
and selected for subsequent boots. Its existing hostapd dependency on an
absent `wlan0` prevented activation from finishing until those pending AP
jobs were stopped; wired access, HDMI capture and USB gadget operation were
checked afterwards. Rock was not rebooted into its new system during this
test.

Trex's complete new configuration is **not activated**: its activation would
also change unrelated services. The publisher was run explicitly, its closure
is GC-rooted at `/nix/var/nix/gcroots/strix-secure-boot-canary`, and signed files
are persistent. Router's cache supplies the boot files independently of
Trex's temporary HTTP selector. Automatic publication and restoration of
that origin selector after a Trex reboot still require activating the Trex
configuration. NFS/RDMA storage services were not restarted for this work.

The initial enforced boot exposed GPU SMU timeouts during stage 2 while
RyzenAdj was stuck applying power settings. NPU power-management errors
and long shutdown delays followed. One later restart returned to PXE after
about four minutes without a physical reset, as confirmed by the operator;
it was slow, not permanently stuck. The earlier unsigned-loader attempt
was inconclusive because no test file was fetched before it was restored.

The canary now sets `strix.automaticPowerTuning = false` in its inventory.
This pauses `ryzenadj`, `curve-optimizer-mqtt` and `ec-su-axb35-config` at
startup while keeping monitoring enabled. A diagnostic boot with exactly
these settings had fresh GPU and NPU telemetry, no SMU/PSP timeouts, no
failed services, and a successful warm restart into firmware within about
a minute. Other hosts keep their existing tuning. The individual command
responsible is still unknown; requalify these writes separately before
reenabling automatic tuning on strix-1. Stock firmware power policy applies.

With firmware showing **User / Secure Boot Enabled / Active**, the second
negative test offered the corresponding unsigned iPXE binary only at the
canary's boot filename. The router logged its completed TFTP transfer, and
firmware displayed **Secure Boot Violation: Invalid signature detected**.
Evidence is `strix-1-unsigned-enforcement-2.png`. The test used a temporary
bind mount over the signed file, with timed unmount as a fallback; the mount
and timer were removed immediately afterwards, the verified cache was
refreshed, and the signed boot path was restored. No unsigned test selection
remains.

The final normal publisher produces the same UKI as the successful diagnostic
configuration. Its system is
`/nix/store/n1h804imvlmzywrk9xslv1m7rxj2l6my-nixos-system-strix-1-26.11.20260916.b1b8759`,
signed UKI SHA-256
`3fba794a5805cb3b306a771cd553f34c5fa8cca46486e83f12fd946a5c0e51d9`.
The recovery USB was regenerated with this payload and reattached at the
persistent configured path. At this stage Strix-2 remained on the ordinary
boot path and Strix-3 was excluded because of an unrelated hardware problem;
the subsequent enrollments are recorded below.

The final restored network boot (`cad35a97-96e8-4b3f-a845-10c6c8fbc490`)
completed with Secure Boot enabled, the expected router URL and system,
both RDMA mounts present, fresh GPU/NPU telemetry, and no failed services
or pending jobs. The final efivar comparison again preserved every original
key and dbx entry. Evidence is `strix-1-final-status.txt` and the final efivar
archive alongside the firmware screenshots.

## Strix-3 enrollment and firmware tuning, September 28

After its separate SPI recovery, Strix-3 retained its restored Bosgame
BeyondMax AXB35-02 firmware 1.07 (September 12, 2025), EC 1.08. No firmware
image was flashed during enrollment. The operator moved Rock's HDMI/USB
cables to Strix-3 and confirmed that its Mellanox adapter was absent during
enrollment. Inventory temporarily selected LAN/NFS storage and disabled its
ConnectX/BlueField fabric configuration. The ConnectX was subsequently
restored, as recorded below. Automatic power tuning remains enabled on
Strix-3.

The fleet certificate was appended through Custom → Expert Key Management
without clearing the TPM or resetting the existing keys. Comparing saved EFI
variables after the signed boot verified unchanged PK, KEK and dbx, and all
five original db entries plus exactly the fleet certificate. Linux reported
`SecureBoot=1`, `SetupMode=0`.

The usual settings were applied through setup and read back from EFI
variables after reboot. Resource offsets were decoded from this board's own
restored Bosgame 1.07 ROM, rather than assuming the FAEX9 database matches.
Bosgame rejects runtime writes to these variables. **Alt+F5**, followed by
Save & Exit and reentering setup, exposes the second Advanced tab. Its
AMD PBS menu contains the MMIO limit and USB/Thunderbolt reservations;
PCI Subsystem Settings → PCI Hot-Plug Settings contains bus padding.

| Setting | Saved value |
| --- | --- |
| Power Mode | Performance |
| Auto Power On after AC loss | Power On |
| Wake on LAN | Enabled |
| iGPU / UMA | UMA_SPECIFIED / 512 MiB |
| Above 4G decoding / ReBAR / PCI hot-plug | Enabled |
| Above 4 GB MMIO limit | 42 bits / 4 TiB |
| PCI bus padding | 5 |
| USB4 reserved buses | 32 |
| USB4 prefetch memory / alignment | 256 MiB / 256 MiB |
| USB4 non-prefetch memory / alignment | 384 MiB / 64 MiB |
| Fast Boot / Quiet Boot | Disabled |
| Network stack / IPv4 PXE | Enabled |
| IPv6 PXE / HTTP boot | Disabled |
| Boot priority | Network first |

Fast Boot's separate hidden Network Stack Driver Support flag remains at its
default; Fast Boot itself is disabled. Native IPv4 PXE was verified with the
Rock mass-storage LUN detached. The power-on setting was read back, but no
additional AC interruption was performed during this enrollment.

The signed native network boot (`91b45de4-4459-4105-9df0-67e1fe9d003f`)
reported `http://192.168.23.31/strix-netboot/secure/strix-3/current/boot.efi`
and system
`/nix/store/y1g3jhm98s9ck533b4kvy6fbjfi1fmzg-nixos-system-strix-3-26.11.20260916.b1b8759`.
Its signed UKI SHA-256 is
`932ba3f6f21c7f6611b21abb8203e79bea2a31a4bc23876df60a388615afdc74`.
The Nix store and `/models` mounted over NFS, no failed services or pending
jobs remained, and RyzenAdj/EC configuration completed without SMU/PSP
timeouts. Scheduled Nix GC and optimisation are disabled for this disposable
NFS overlay.

An enforcement test temporarily served the corresponding unsigned Strix-3
UKI at only Strix-3's cached URL, with a timed unmount safeguard. Its SHA-256
matched the unsigned build and `sbverify --list` confirmed no signature
table. Signed iPXE downloaded it but rejected execution with `0x7f04818f`
([EFI image loading error](https://ipxe.org/7f04818f)); after its retry the
board returned to setup. `strix-3-unsigned-rejection.png` captures the error.
The shared signed iPXE loader and Strix-1's UKI were untouched. The test bind
mount, timer and temporary unsigned file were removed, the router cache was
refreshed successfully, and the signed UKI hash was verified again.

The restored signed network boot
(`fa91d777-19df-4d01-bc3c-21762ac31b15`) again reached the expected system
with Secure Boot enabled, both NFS mounts, no failed services or pending
jobs, and unchanged tuning and vendor keys. Rock's verified Strix-3 recovery
image was reattached afterwards at its persistent configured path. Router
and Rock configurations are activated and selected for their next boot;
Trex publication remains explicitly managed as described above. The
publisher check passes with both Strix-1 and Strix-3 selected.

Evidence is retained under `artifacts/strix-secure-boot-20260928/` in the main
checkout: `strix-3-final-status.txt`, `strix-3-tuning-readback.txt`, EFI
variable archives, the Bosgame-specific decoded question map and KVM
screenshots. The raw Linux write attempt in `strix-3-firmware-tuning.log`
failed at the first variable without changing it; the saved settings above
were subsequently applied through firmware setup.

## Strix-3 return to NVMe/RDMA, September 28

After the operator restored its adapter, Linux detected both ConnectX-5
functions at `43:00.0` and `43:00.1`. The cabled `b8:59:9f:54:db:e9` port
trained at 100 Gbit/s over PCIe Gen3 x4. Inventory now uses the normal
NVMe/RDMA store and models paths again. BlueField remains disabled because
only the ConnectX-5 is present. The temporary NFS recovery generation is
retained for deliberate rollback.

Signed native PXE boot `094edded-13ed-4f7a-affb-b4f63d6c8bb4` loaded system
`/nix/store/x5896f5f8nlhnp7klq0c9hc6dapkihbv-nixos-system-strix-3-26.11.20260916.b1b8759`.
Its signed UKI SHA-256 is
`040e051def5ffb6a3fd094559c782e5d88ef543d870cca5a9c29fdf9eac39a1e`.
The initrd copied 53.1 GiB into the private boot volume in about five minutes;
this is the existing runtime store population, not an EROFS image.
Secure Boot, all recorded firmware tuning and preservation of the original
vendor key databases were verified again.

After stage 2, RDMA stalled while small fabric pings still worked and larger
packets failed. Jumbo pings recovered as Strix-4 entered Linux, and Strix-3's
boot controller reconnected automatically at 21:43:34 CEST after 16 attempts.
Both controllers then reported `live`; `/nix` was read-write, `/models`
read-only, and direct 64 MiB reads from each volume completed at about
1.1 GB/s. No failed services or pending jobs remained. Neither shared storage
services nor the switch were restarted or reconfigured.

The packet-loss cause is not established. Jumbo traffic failed again during
Strix-4's unsigned-image test, while its firmware was trying Mellanox PXE.
Reapplying Strix-3's MTU through 8996 then 9000 restored jumbo pings with both
controllers still `live`. Both hosts' `mstflint` readbacks report base GUID
`b8599f030054dbe4`, despite different Linux port MACs. The operator confirmed
that **Strix-1/2 share a NIC, and Strix-3/4 share a NIC**. This supersedes
the old inventory's inference of independence from host-visible identities.
Both report host chaining and multi-port VHCA disabled; these flags do not
establish physical independence. Do not change port ownership or flash NIC
firmware based on this incident. The observations support shared-port MTU
reconfiguration during firmware boot, but the exact driver action was not
traced. Peer storage can be interrupted during firmware work; this remains
an operational limitation, not a Secure Boot verification failure.
Strix-3 also reported a Mellanox module high-temperature event. Readback
showed an adapter sensor at 91°C and its active cable at 75°C. The operator
increased the fan speed; readings subsequently fell to 65°C and 57°C and the
alarm cleared. After Strix-4's final reset, Strix-3's boot controller recovered
again at 21:50:28 CEST. Evidence includes
`strix-3-rdma-final-status.txt`, `strix-3-rdma-tuning-readback.txt`,
`strix-3-rdma-efivars.tar` and `strix-3-mellanox-diagnostics.txt`.

## Strix-4 enrollment and firmware tuning, September 28

Rock's HDMI/USB moved to Strix-4 and its configuration now selects the
Strix-4 signed recovery disk. The operator powered on the host. It retains
Bosgame BeyondMax AXB35-02 BIOS 1.07 (September 12, 2025), EC 1.08; no BIOS
image was flashed. Its initial EFI snapshot reported `SecureBoot=0`,
`SetupMode=1`, with PK, KEK, db and dbx absent. The firmware's factory key
databases were installed, then the fleet certificate was appended to db.
No general setup defaults or TPM reset was performed.

The first signed native PXE boot (`31db3774-c38b-40f3-8240-ad5971ef0078`)
reported `SecureBoot=1`, `SetupMode=0`, `DeployedMode=1`. PK, KEK and dbx
matched the firmware's corresponding `*Default` variables byte-for-byte
excluding efivar attributes. All five factory db entries were present,
with exactly one added fleet certificate: PK 1, KEK 3, db 6, dbx 430.
The saved firmware tuning matches the table above; Strix-4's preexisting
SR-IOV setting remains enabled. Power-on-after-AC-loss was read back without
an additional physical power interruption.

The running system is
`/nix/store/w8cw7gfpdfah4x3fr0kdpwccqp9bfxb3-nixos-system-strix-4-26.11.20260916.b1b8759`.
Signed UKI SHA-256:
`6542dfb4c0495573b6dcee80097afe26f706422a7fc58d7f982bc1e94c1e3ef4`.
The UKI is approximately 100 MiB and uses the normal NVMe/RDMA runtime store.
The first signed boot reported the router's Strix-4 URL, `/nix` read-write,
`/models` read-only, no failed services and no pending jobs. Direct boot-volume
reads completed at about 1.2 GB/s. Automatic power tuning remains enabled.

The enforcement test served the matching unsigned UKI only at Strix-4's
cached URL, using a read-only bind mount and an eight-minute automatic
unmount safeguard. Its HTTP SHA-256 matched the unsigned build and the file
had no signature table. Signed iPXE downloaded it and rejected execution
with `0x7f04818f`; `strix-4-unsigned-check-2.png` records the failure.
The bind mount, fallback timer and unsigned file were removed immediately,
the cache refreshed, and the signed hash verified. The shared signed iPXE
binary and other hosts' UKIs were not changed.

The restored signed network boot (`9b3b6e63-15aa-4ef3-9f0d-ed87a26e5155`)
again reported the expected router URL and system. All enrolled key variables,
Secure Boot state and decoded tuning matched the first signed boot. Both
Strix-3 and Strix-4 had live boot/models controllers, correct mount modes,
no failed services or pending jobs, and successful direct reads from both
volumes at approximately 0.9 GB/s during the final concurrent checks.
GPU/NPU exporters were running and power tuning had completed. The final
Strix-4 kernel log had two display-controller `REG_WAIT` warnings during
HDMI handoff, but no SMU/PSP or RDMA connection failures. Mellanox readings
on both hosts were 64°C/54°C after the fan adjustment.

Rock's signed Strix-4 recovery disk is reattached read-only at the configured
persistent path. Router and Rock configurations are activated and pinned;
Trex's complete configuration remains unactivated as explained above.
Strix-2's subsequent enrollment is recorded below. Final evidence includes
`strix-4-final-status.txt`, `strix-4-final-tuning-readback.txt`,
`strix-4-efivars-final.tar` and `strix-3-rdma-after-strix4.txt`.

## Strix-2 enrollment, September 28

The operator moved Rock's HDMI/USB to Strix-2. The console initially showed
an existing initrd failure connecting its private boot volume. A warm restart
restored the RDMA connection and began copying its runtime store. Its
existing GMKtec EVO-X2 1.04 golden firmware remains installed; no BIOS flash
or defaults reset was performed. All 26 settings decoded from the GMK 1.04
Setup/AMD PBS definitions already matched the fleet settings, including
performance mode, AC power-on, 42-bit MMIO, PCI bus padding 5, USB4 buses 32,
prefetch/alignment 256 MiB, 512 MiB UMA and IPv4 PXE. Unlike Strix-3/4,
its hidden Network Stack Driver Support flag is also enabled.

Inventory selects its signed network path, and Rock now targets the signed
Strix-2 recovery disk. The publisher, router and Rock builds completed, and
router/Rock activation and cache refresh succeeded. The other three signed
UKIs were retained unchanged. Strix-2's UKI is approximately 115 MiB; its
recovery disk is 149 MiB. Its system is
`/nix/store/i643d9jsc9m1wn1m8a50ibr21wlw1hj8-nixos-system-strix-2-26.11.20260916.b1b8759`,
and its signed UKI SHA-256 is
`20a94e03cde935fe1aea234875542abd3e95711cc925be851646bd40ea3626e0`.

The recovered raw boot (`8a78d10b-b38f-411f-ab8d-c70477389b1d`) reported
`SecureBoot=0`, `SetupMode=0`. Its fresh EFI snapshot contained PK 1, KEK 3,
db 6 and dbx 430 entries; none of the db entries was the fleet certificate.
Through Custom → Expert Key Management → db → Append, the fleet DER
certificate was added with owner GUID
`26dc4851-195f-4ae1-9a19-fbf883bbb35e`. Firmware reported success. Existing
keys were retained, and Secure Boot was enabled using F10 Save & Reset.
The TPM was not cleared.

An isolated unsigned-UKI test at Strix-2's cached URL used the same read-only
bind mount and eight-minute automatic-unmount safeguard as Strix-4. The
HTTP hash matched the unsigned build, which had no signature table. Signed
iPXE fetched it and rejected execution with `0x7f04818f`, captured in
`strix-2-unsigned-check-2.png`. The mount, timer and test file were removed,
the signed hash restored and router cache refreshed successfully. The native
signed network boot then reached the initrd and connected its RDMA volume.
Strix-1's boot and models controllers stayed live during these operations.

The final signed boot (`085e2154-c383-4f1d-bbd9-277992ea2bda`) reached the
expected system and reported the router's Strix-2 URL in `bootctl status`,
with `SecureBoot=1`, `SetupMode=0`. Comparing its snapshot against the
fresh pre-enrollment snapshot confirmed PK, KEK and dbx were byte-for-byte
unchanged, with all six original db entries plus exactly one fleet
certificate. All 26 decoded tuning values were unchanged; Quiet Boot
remains disabled. AC power-on was read back without another physical
power interruption.

Both controllers were live, `/nix` read-write and `/models` read-only.
Direct 64 MiB reads from each volume completed at approximately 1 GB/s.
The integrated GPU/NPU exporters were running and Ryzen/CPU power tuning
completed successfully. The kernel had two display-controller `REG_WAIT`
warnings during HDMI handoff, but no SMU/PSP initialization or RDMA
connection failure.

A separate hardware/workload issue remains: PCI enumeration contains no
V620 GPUs, while inventory expects four. `v620-powercap` reports
`expected 4 reference V620s, found 0` and retries on its existing timer;
the dependent `qwen38-serve` service consequently did not start. The cause
of the missing external GPUs was not established. Their configuration was
retained; successful Secure Boot acceptance does not imply this workload
is available.

Final fleet checks at 22:20 CEST confirmed all four hosts have Secure Boot
enabled and both storage controllers live. Strix-1, Strix-3 and Strix-4
had no failed units or pending jobs. Strix-1's earlier TPM setup/login
failures reported `0x921` (dictionary-attack lockout). Read-only TPM
properties showed the lockout had already expired naturally; restarting
those two services succeeded, with lockout counter zero and the original
SRK fingerprint unchanged. No TPM clear or lockout-policy change was used.

Rock's Strix-2 signed recovery disk is reattached read-only. Evidence
includes `strix-2-final-status.txt`, `strix-2-final-health.txt`,
`strix-2-final-tuning-readback.txt`, `strix-2-efivars-final.tar`, each host's
`*-fleet-final-state.txt`, and `strix-1-tpm-recovered.txt` in the main
checkout's artifact directory. Router/Rock remain activated and pinned;
Trex publication retains the activation limitation documented above.
