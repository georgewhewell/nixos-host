# trex serial console & BMC out-of-band access

trex is an ASRock **WRX90 WS EVO** (Threadripper PRO 7985WX) with an AMI
MegaRAC BMC (ASPEED AST2600). This is how to reach it out-of-band — over
serial (SOL) for normal use, and the fuller BMC surface for recovery.

## Credentials & addresses

- BMC IP: **192.168.23.10** (`trx90bmc` in network.nix, LAN .10).
- BMC login: **`admin`** / password in `pass trx90bmc/admin`.
- In-band IPMI also works from trex itself (`/dev/ipmi0`, `ipmitool` KCS).

## Serial console (normal use)

The OS console is on **ttyS1 (COM2, I/O 0x2F8)** — the UART the BMC bridges to
SOL. Kernel cmdline carries `console=tty0 console=ttyS1,115200n8` (tty0 first
so the ASPEED video KVM still shows everything; ttyS1 last so it's
`/dev/console` and gets a login getty). Set in `machines/x86/trex/default.nix`.

Connect to the live console over IPMI Serial-over-LAN:

```sh
ipmitool -I lanplus -H 192.168.23.10 -U admin -P "$(pass trx90bmc/admin)" sol activate
#   ~.  to disconnect,  ~?  for help
```

Alternate path — SOL over SSH (BMC `solssh` service, port 22):

```sh
ssh admin@192.168.23.10        # AMI CLP shell; start the SOL session from there
```

## BIOS / POST over serial (lockout insurance) — TODO

The OS console above is independent of the BIOS. To get **POST and the BIOS
setup menu** over serial (so a CMOS reset can't lock us out), the firmware's
own console redirection must be on. It is **not currently enabled** (no ACPI
SPCR/DBG2 table is published). Enable it once, at the BMC video KVM:

- BIOS → Advanced → **Serial Port Console Redirection** → §3.4.8 **COM0 →
  Console Redirection = Enabled**, Terminal Type **VT-UTF8**, **115200 / 8 /
  None / 1**, Flow Control **None**.

This setting lives in the AMI `Setup` EFI varstore, which is **not exposed to
the OS in efivarfs**, so it cannot be set from Linux / `bios-setup-var` — it is
genuinely BIOS-menu-only. After enabling, a reboot should publish an SPCR
table (`ls /sys/firmware/acpi/tables/SPCR`) and POST text will appear on SOL.

## Video KVM (fallback when serial redirection is off)

- Supported path: AMI **H5Viewer** over HTTPS (443) — needs a browser.
- The BMC also runs a **VNC server on 5901**, but it is AMI *single-port,
  TLS-wrapped* VNC: connect with TLS **SNI = the BMC hostname**
  (`AMI9C6B00573177`), TLS 1.2, `ALL:@SECLEVEL=0` — that completes the TLS
  handshake, but the VNC backend is session-gated and does not serve raw RFB
  without either the web-session authorisation flow or disabling global
  single-port mode (a BMC-wide change; `~/bf2-fw-backup/bmc-services-backup.json`
  on fuckup is a config backup for rollback). Not currently usable headless.
- Full **Redfish** (power, sensors, boot override) works with the `pass` creds:
  `curl -sk -u admin:$(pass trx90bmc/admin) https://192.168.23.10/redfish/v1/...`

## Reboot into firmware setup

```sh
ssh trex.lan.satanic.link 'sudo systemctl reboot --firmware-setup'
```

Clean OS shutdown (flushes ZFS/NFS) + UEFI boot-to-firmware flag. Note: trex is
the fleet's NFS root — every netbooted strix freezes until it is back.

## Memory (EXPO 7200) & ECC monitoring

- 8× V-color OC R-DIMM (registered ECC), **DDR5-7200 EXPO**, validated over ~2
  years. Confirmed trained at 7200 across all 8 channels (SMBIOS
  "Configured Memory Speed").
- The board reverts DRAM OC to JEDEC **4800** after a hard fault / failed train
  (AMD Memory Context Restore, by design). If SMBIOS shows 4800, the profile
  dropped — **re-apply EXPO in the BIOS** and reboot.
- `hardware.rasdaemon.enable` logs per-DIMM ECC. Check with
  `sudo ras-mc-ctl --error-count` (CE/UE per channel) and
  `sudo ras-mc-ctl --summary`. Rising CE on one channel = that DIMM marginal
  (usually thermal); WHEA/MCE = core/fabric-OC error (not covered by ECC).
