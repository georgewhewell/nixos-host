# Strix firmware Secure Boot

As of September 28, all four hosts have completed enrollment and signed
network boot. Final live readbacks on Strix-1 through Strix-4 report
`SecureBoot=1`, `SetupMode=0`, with both NVMe/RDMA controllers live.

The lightweight path signs iPXE and a unified kernel image (UKI). The UKI
contains the kernel, initrd and embedded command line. It does **not** copy
the system closure into an EROFS image. The September 28 Strix-1 UKI is about
100 MiB, and its GPT recovery disk is 134 MiB. Strix-3's initial LAN/NFS
enrollment used an 82.5 MiB UKI and a 117 MiB recovery disk; after its
ConnectX was restored it returned to the normal approximately 100 MiB UKI.

Hosts normally use a private NVMe/RDMA Nix store and read-only models snapshot.
The initrd seeds that Nix store from Trex. A host without a fabric adapter can
explicitly select `netbootStorage = "nfs"`: its store is Trex’s read-only NFS
export with a disposable 2 GiB writable overlay, and `/models` uses NFS.
Scheduled local garbage collection and store optimisation are disabled in
this mode because they would scan the shared store. It is not an automatic
RDMA fallback and the writable overlay is unsuitable for large builds.
Firmware verification ends at the signed boot payload: this is not verified
userspace, kernel lockdown, rollback prevention, or remote attestation.
Full runtime verification is separate work; the earlier EROFS/dm-verity
implementation remains on `secure-boot-integration` (`05cd800`, `679cc20`).

The original Codex thread was **Enable secure boot**, September 16–17,
`01a0aaed-eba3-76c1-92c8-edbd65a67c64`, started in `nix-strix-halo` but working
on this repository. Its large runtime artifacts were removed at the user's
request. Do not restore those images for the firmware-only rollout.

## Configuration and publication

`network.hosts.<host>.strix.secureBoot = true` enables a host. All four Strix
hosts are enrolled. Strix netboot now requires this setting: client, router
and origin configurations reject an unsigned selection. The raw kernel/initrd
bundle, unsigned iPXE loaders, legacy HTTP routes and `strix-netboot-update`
helper have been removed. The router offers only signed iPXE over PXE/HTTP;
other machines' storage exports are unchanged.
Trex builds each enabled host's `system.build.strixSecureBoot` and publishes
signed artifacts under `/var/lib/strix-secure-boot`. Signed generations are
retained and `current` changes atomically only after signature and payload
verification. Automatic garbage collection of signed generations is not
implemented.

The private db key is the existing fleet key, reencrypted in the dedicated
`secrets/strix-secure-boot.yaml` for Trex and the two operator PGP keys. SOPS
installs it root-only at `/run/secrets/strix-secure-boot-db-key`. It never
enters a Nix derivation or the public HTTP tree. The public certificate is
`secrets/strix-secure-boot-db.pem`, SHA-256:

```
D5:7E:CD:E7:4A:A7:70:45:77:19:86:10:05:05:2C:91:7E:CC:A8:29:C6:29:6A:FC:5A:F1:7A:9A:94:43:B0:F2
```

Build and run the publisher on Trex after provisioning the SOPS secret:

```sh
nix build --out-link result-publisher \
  .#nixosConfigurations.trex.config.system.build.strixSecureBootPublisher
sudo ./result-publisher/bin/strix-secure-boot-publish
```

On a deployed Trex configuration, `strix-secure-boot-publish` is also on
PATH and its service runs on activation/boot. Router's
`strix-secure-boot-sync-ipxe` caches iPXE and each enabled host's UKI in its
persistent `/var/lib/strix-secure-boot`. It verifies signatures and the host
identity in the signed command line before atomically selecting a retained
generation. It serves `/strix-netboot/secure/` directly. Failed refreshes
leave the previous files available, including after router or Trex restarts.
Trex still supplies NFS/RDMA runtime storage. Cache generations are retained;
remove obsolete ones deliberately after confirming rollback requirements.

After every publication, refresh the router cache:

```sh
ssh root@192.168.23.31 systemctl restart strix-secure-boot-sync-ipxe.service
```

UKI updates need no DHCP change. Publication roots each retained generation's
source bundle under `/nix/var/nix/gcroots/strix-secure-boot/`, keeping its
system closure available for rollback. Remove that root when deliberately
retiring the corresponding signed generation. Keep the current publisher
closure GC-rooted too, so its command and per-MAC selectors remain available.
The manually deployed publisher is rooted at
`/nix/var/nix/gcroots/strix-secure-boot-publisher`.

## Recovery USB and enrollment

Build a recovery disk from an already signed UKI:

```sh
nix build --out-link result-recovery-tool \
  .#nixosConfigurations.trex.config.system.build.strixSecureBootRecovery
./result-recovery-tool/bin/strix-secure-boot-recovery \
  /var/lib/strix-secure-boot/strix-1/current/boot.efi \
  secrets/strix-secure-boot-db.pem strix-1-secure.img
```

The tool verifies the signature and creates a new regular GPT image with a
FAT ESP. It includes `EFI/BOOT/BOOTX64.EFI` and public `strix-db.cer` (DER).
It refuses existing outputs and block devices. Copy it to Rock's persistent
`/var/lib/kvm-bootstrap/strix-1-secure.img`; `services.kvmBootstrap.imageFile`
selects it for the USB gadget. Regenerate deliberately when updating the
recovery generation. This image still needs the host’s configured RDMA/NFS
runtime storage; it is a signed alternate loader, not an offline OS.
Rock currently targets Strix-2. Always change `targetHost` and provision the
corresponding signed image when moving the KVM cable. Its default path is
`/var/lib/kvm-bootstrap/<targetHost>-secure.img`; there is no unsigned USB
bootstrap fallback.

Strix-1 firmware: GMKtec EVO-X2 1.04, AMI Aptio. With the Rock HDMI and HID
attached, `systemctl reboot --firmware-setup` enters setup. The September 28
firmware was already in User mode with Custom key management. Preserve
existing PK, KEK, db and dbx; no Setup Mode reset or TPM clear is needed.

Append the fleet certificate using:

1. Security → Secure Boot → Expert Key Management.
2. Authorized Signatures (db) → Append.
3. Answer **No** to factory defaults, select the USB filesystem, then
   `strix-db.cer` and **Public Key Certificate**.
4. Accept an owner GUID and confirm Append. Record success and key counts.
5. Enable Secure Boot, save/reset, verify signed boot and test unsigned rejection.

The firmware assigned owner GUID `26dc4851-195f-4ae1-9a19-fbf883bbb35e`.
Strix-1's baseline had PK: 1, KEK: 3, db: 4, dbx: 245 entries. An efivar backup and
KVM screenshots are retained in the main checkout's
`artifacts/strix-secure-boot-20260928/` (not committed).

## Firmware settings and operating limits

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

Strix-1/2 use GMKtec 1.04; Strix-3/4 use Bosgame 1.07. Decode setup variables
against the matching ROM. Save with F10 on GMK and F4 on Bosgame; avoid
loading defaults. SR-IOV and hidden fast-boot flags retain their recorded
per-host values; see the rollout record for details.

The NIC is shared by Strix-1/2 and by Strix-3/4. Firmware boot or a port
reset can disturb the peer's MTU and active RDMA storage. Strix-1's automatic
power writes remain paused after observed SMU/PSP timeouts; its firmware
performance setting remains enabled. Strix-2 currently sees no V620 GPUs,
so its configured four-GPU power cap and dependent Qwen workload cannot
start. These are separate operational issues.

## Deployment status

All four hosts passed signed boot and unsigned-image rejection. Router and
Rock ran the enrolled fleet configuration. Trex's full configuration remains
unactivated because it also changes unrelated services; its publisher was
run explicitly, with persistent signed artifacts and GC roots. Router's
persistent cache serves the signed boot files independently of the origin.
Automatic Trex publication and origin restoration after a reboot still
require deploying its configuration. The cleanup changes retire raw paths
on deployment; they do not require re-enrollment or host reboots.

Do not delete signed rollback generations, their GC roots, TPM credentials,
vendor key databases, or the RDMA volumes as part of raw-path cleanup.
Firmware snapshots and KVM evidence remain outside Git in the main
checkout's `artifacts/strix-secure-boot-20260928/`.

## Verification

```sh
nix build --no-link \
  .#checks.x86_64-linux.strix-secure-boot-publisher \
  .#checks.x86_64-linux.strix-secure-boot-config
colmena build --on router,rock-5b
```

The publisher check exercises real PE signatures, tampering, mismatched
keys, command-line substitution, retained generations and atomic selection.
The configuration check rejects unsigned netboot, verifies both DHCP
transports select signed iPXE, checks raw HTTP routes and bundles are absent,
and confirms Rock selects the matching signed recovery image.

Hardware acceptance requires `SecureBoot=1`, `SetupMode=0`, intact vendor
keys/dbx, the expected signed system and boot URL, working runtime storage,
and unsigned EFI rejection. See the [rollout record](strix-secure-boot-rollout-20260928.md)
for hashes, boot IDs, firmware readbacks and incident evidence.
