# Nits

Project-local review queue for issues that are real but outside the active
change. Entries should be concrete, evidence-backed, and removed when fixed.

## Open

- [ ] BlueField-2's SSH host key is not stable across the recovery/deployment
  path. Its current Ed25519 fingerprint is
  `SHA256:ajMQCttM3D7OdBEBSIX4SR+pDH98bna4sC7lB5mRacY`, while the retired key in
  operators' `known_hosts` blocks unattended diagnostics. Persist the host key
  and publish it from the inventory used by declarative SSH clients.
- [ ] BeeGFS clients acquire a new management identity when a Strix host moves
  between ephemeral netboot root and disk root. Stale identities can exhaust
  the five-client license and prevent `/mnt/beegfs` from mounting. Give each
  host a stable client identity or add narrowly scoped stale-client cleanup.
- [ ] `services/buildfarm-executor.nix` pins rock's retired SSH host key. The
  current Ed25519 fingerprint is `SHA256:NNlVdt5OKPIR8CNMGcGylaNXf6h2E/hBi249FYhfmTE`;
  the stale key prevents the declarative builder entry from connecting after
  DNS resolves the host correctly.
- [ ] `profiles/router/ap.nix` installs firmware for hardware that rock does
  not have (`ipw2200`, `rtl8192su`, `zd1211`, B43, Xbox One, and DVB firmware).
  Reconcile the firmware closure with the PCI/USB inventory and the pruned
  kernel config.
- [ ] The `*-cross` NixOS configurations cross-compile complete system
  closures. For rock this expands a routine deploy into hundreds of uncached
  userspace derivations. Prefer or expose kernel-only cross outputs where the
  native userspace is cacheable.
- [ ] `profiles/router/ap.nix` currently combines generic AP policy, Rock 5B
  board/kernel policy, and build-platform selection. Split the board-specific
  kernel and firmware policy from the reusable AP service profile.
