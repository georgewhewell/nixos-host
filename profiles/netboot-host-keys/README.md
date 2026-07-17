# TPM-sealed host keys for netboot clients

One `<hostname>.cred` per diskless host: the ed25519 ssh host key sealed to
that machine's TPM with `systemd-creds encrypt --with-key=tpm2 --tpm2-pcrs=""`.
The blobs are safe to commit — only the enrolling machine's TPM can unseal
them. `profiles/netboot-client.nix` decrypts the blob during boot activation,
restoring a stable ssh identity and the sops-nix age key.

Enrollment (once per host, on the host):

    # with the canonical key in place at /etc/ssh/ssh_host_ed25519_key,
    # or pass a path to it (e.g. one recovered from the old NVMe root):
    sudo strix-netboot-enroll [key-path]
    scp <host>:/tmp/<host>.cred profiles/netboot-host-keys/<host>.cred

If the sealed key is a *new* identity (not the one already in `.sops.yaml`),
update the host's age recipient there (the enroll script prints it) and run
`sops updatekeys` on the affected secrets.

A BIOS update or CMOS reset can clear the fTPM, invalidating the blob; the
host then falls back to fresh-keys-per-boot until re-enrolled. Keep the
underlying private keys escrowed so re-enrollment doesn't change identity.
