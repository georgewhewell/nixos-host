# NanoKVM fleet deployment

This directory owns stage-2 SD, NFS and NBD configurations and their host
network/root-serving policy. `inputs.nanokvm` supplies reusable SG2002
hardware support and its standalone, RAM-only USB initrd.

`fleet.nix { inherit inputs; }` exposes:

- `boards`: the migrated board/kernel/profile catalog, as NixOS modules;
- `artifacts pkgs`: FIT, NFS/NBD, rootfs and kexec builders for fleet configs.

`machines/default.nix` consumes these modules for `nanokvm`, `licheerv` and
`claw`. The trex and workstation USB services consume `artifacts` built from
the fleet's own `nixosConfigurations`; no upstream runner configures their
networking. The local overlay supplies the NBD client, EROFS closure builders
and host SSH-key injection helper.

Build the fleet configurations/images using this flake's normal outputs:

```sh
nix build .#nixosConfigurations.claw.config.system.build.initialRamdisk
nix build .#nixosConfigurations.licheerv.config.system.build.initialRamdisk
nix build .#nixosConfigurations.nanokvm.config.system.build.sdImage
```

For a local cross-repository change, test with
`--override-input nanokvm ../nixos-nanokvm --no-write-lock-file`. Update the
input pin when publishing both changes together. Do not point friends at
these fleet configurations: use the upstream `boards.<board>.mainline.initrd.default.bundle`
and its standalone instructions instead.

The migrated catalog intentionally preserves its previous behavior,
including private-link debug sockets and development passwords. It is not
an internet-facing or shareable appliance. Review those policies before
deploying outside the trusted fleet. Historical stage-2 evaluation tests are
preserved under `tests/`; upstream now checks the initrd-only contract.
