{ config, lib, ... }:
let
  persist = config.sconfig.impermanence.persistentStoragePath;

  persistentDirectories = [
    { directory = "/var/log/journal"; user = "root"; group = "systemd-journal"; mode = "2755"; }
    { directory = "/var/lib/dnsmasq"; user = "dnsmasq"; group = "root"; mode = "0755"; }
    { directory = "/var/lib/fail2ban"; mode = "0750"; }
    { directory = "/var/lib/frigate"; user = "frigate"; group = "frigate"; mode = "0750"; }
    { directory = "/var/cache/frigate"; user = "frigate"; group = "frigate"; mode = "0750"; }
    "/var/lib/fwupd"
    { directory = "/var/lib/hass"; user = "hass"; group = "hass"; mode = "0700"; }
    { directory = "/var/lib/mosquitto"; user = "mosquitto"; group = "mosquitto"; mode = "0700"; }
    "/var/lib/nftables"
    "/var/lib/systemd/linger"
    { directory = "/var/lib/tor"; user = "tor"; group = "tor"; mode = "0700"; }
    "/var/lib/unifi"
    "/var/lib/unifi-db"
    { directory = "/root/.config/gcloud"; mode = "0700"; }
  ];

  seedDirectories = map (entry:
    if lib.isString entry
    then entry
    else entry.directory
  ) persistentDirectories;
in
{
  # Persist journals across reboots to diagnose intermittent crashes;
  # /var/log/journal is bind-mounted from btrfs /persist above so logs
  # survive the ephemeral tmpfs root (overrides impermanence mkDefault).
  services.journald.storage = "persistent";
  # Cap on-disk journal so it cannot fill /persist, but keep enough history to
  # span several boots — 64M vacuumed away the logs of the panic/watchdog
  # reboots that truncated HA's .storage files, leaving them undiagnosable.
  services.journald.extraConfig = "SystemMaxUse=256M";

  # The router image keeps /nix and /persist on the same small btrfs device.
  # Treat old Nix generations as disposable here; service state is the thing
  # that needs room to keep writing safely.
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = lib.mkForce "--delete-old";
    randomizedDelaySec = lib.mkForce "20min";
  };
  nix.optimise.dates = "daily";
  nix.settings = {
    min-free = lib.mkForce 1073741824; # 1 GiB
    max-free = lib.mkForce 3221225472; # 3 GiB
  };

  sconfig.impermanence = {
    enable = true;
    persistentStoragePath = "/persist";
  };

  disko.imageBuilder = {
    name = "router-usb-btrfs";
    copyNixStoreThreads = 8;
  };

  disko.devices = {
    disk.router-usb = {
      type = "disk";
      device = "/dev/disk/by-diskseq/1";
      imageName = "router-usb-btrfs";
      imageSize = "13G";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            name = "ESP";
            start = "1M";
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" "-L" "router-usb" ];
              subvolumes = {
                "/persist" = {
                  mountpoint = "/persist";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                    # Flush dirty data before each metadata commit so a renamed
                    # file (HA writes .storage via atomic rename without fsync)
                    # can never be observed empty after a panic/watchdog reboot.
                    # btrfs lacks ZFS's transactional crash-consistency, which is
                    # why HA state started corrupting after the ZFS->btrfs move.
                    "flushoncommit"
                  ];
                };
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "mode=755"
        "size=8G"
      ];
    };
  };

  fileSystems."/" = lib.mkForce {
    device = "tmpfs";
    fsType = "tmpfs";
    neededForBoot = true;
    options = [
      "mode=755"
      "size=8G"
    ];
  };

  fileSystems."/nix".neededForBoot = true;
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/boot" = lib.mkForce {
    device = "/dev/disk/by-partlabel/disk-router-usb-ESP";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  boot.supportedFilesystems = lib.mkForce [ "btrfs" "vfat" ];
  boot.initrd.supportedFilesystems = lib.mkForce [ "btrfs" ];
  boot.initrd.availableKernelModules = [
    "sd_mod"
    "uas"
    "usb_storage"
    "xhci_hcd"
    "xhci_pci"
  ];
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  environment.persistence.${persist}.directories = persistentDirectories;
  sconfig.impermanence.seedExisting.directories = seedDirectories;
}
