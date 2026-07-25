# Read-only CS0 protection preflight

UTC start: `2026-07-25T08-50-56Z`

Host: `strix-4`

Device: `0000:c4:00.0`, `1000:c010`, revision `0xb0`

Tool:
`/nix/store/sjxmbvcyl1nygkvlxjqx9rzrhdyw6jcd-pexctl-0.1.0/bin/pexctl`

Command:

```console
sudo pexctl device flash-status --bdf 0000:c4:00.0 --json
```

The raw result is [`flash-status.json`](flash-status.json). Status registers
were SR1 `0x00`, SR2 `0x02`, and SR3 `0x00`: the flash was idle, WEL was
clear, no erase/program was suspended, BP and CMP were clear, WPS selected
status-register protection, and QE was the only decoded set bit. The new
sector-0 programming preflight returned `true`.

The boot ID before and after the command was
`758399aa-a216-4733-90ad-eab6141f7c18`. A mapped SBR read immediately
afterward remained 2896 bytes with SHA-256
`f4e0bf5d1d01d3f8daccc7c9c792cf0174e509a725379a646c9704c2cd4caae5`.
The existing `/tmp/pexctl-station4-plan-20260725-v4` still passed all eleven
artifact and semantic checks.

This observation issued JEDEC/status reads and a mapped SBR read only. It did
not issue Write Enable, Write Disable, status-register writes, erase, page
program, PEX reset, host reset, or reboot.
