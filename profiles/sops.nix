{
  config,
  lib,
  ...
}: let
  impermanence = config.sconfig.impermanence;
  sshHostKeyPath =
    if impermanence.enable
    then "${impermanence.persistentStoragePath}/etc/ssh/ssh_host_ed25519_key"
    else "/etc/ssh/ssh_host_ed25519_key";
in {
  # sops-nix configuration - use SSH host key for decryption
  # This is imported by host machines but not containers
  # (containers bind-mount secrets from the host)
  sops.age.sshKeyPaths = [sshHostKeyPath];

  services.openssh.hostKeys = lib.mkIf impermanence.enable [
    {
      path = "${impermanence.persistentStoragePath}/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
    {
      path = "${impermanence.persistentStoragePath}/etc/ssh/ssh_host_rsa_key";
      type = "rsa";
      bits = 4096;
    }
  ];

  sconfig.impermanence.seedExisting.files = lib.mkIf impermanence.enable [
    "/etc/ssh/ssh_host_ed25519_key"
    "/etc/ssh/ssh_host_ed25519_key.pub"
    "/etc/ssh/ssh_host_rsa_key"
    "/etc/ssh/ssh_host_rsa_key.pub"
  ];
}
