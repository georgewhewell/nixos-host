{...}: {
  # sops-nix configuration - use SSH host key for decryption
  # This is imported by host machines but not containers
  # (containers bind-mount secrets from the host)
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
}
