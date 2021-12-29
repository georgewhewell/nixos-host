{ config, pkgs, ... }:

{
    # Ref: https://github.com/sgillespie/nixos-yubikey-luks
    # Howto:
    # - nix-shell https://github.com/sgillespie/nixos-yubikey-luks/archive/master.tar.gz
    # read -s LUKS_KEY
    # echo -n "$LUKS_KEY" | hextorb | sudo cryptsetup open /dev/nvme0n1p3 encrypted --key-file=-
    # sudo mount /dev/mapper/vg0-nixos /mnt
    # sudo mount /dev/nvme0n1p1 /mnt/boot/
    # sudo nixos-enter

    # mkdir -p /boot/crypt-storage
    # read -s SALT
    # ITERATIONS=1000000
    # echo -ne "$SALT\n$ITERATIONS" > /boot/crypt-storage/default

    # ln -s -f /etc/nixos/machines/x86/yoga/configuration.nix /etc/nixos/configuration.nix
    # nixos-install --root / -I home-manager=https://github.com/rycee/home-manager/archive/master.tar.gz --no-root-password
    
    boot.loader = {
        efi = {
            canTouchEfiVariables = true;
            efiSysMountPoint = "/boot";
        };
        grub = {
            efiSupport = true;
            device = "nodev";
        };  
    };

    boot.kernelParams = [ "boot.shell_on_fail" ];
    boot.initrd = {
        kernelModules = [
            "dm_crypt" "trusted" "encrypted_keys"
            "r8152" "nvme" "vfat" "nls_cp437" 
            "nls_iso8859-1" "usbhid" "cbc"
            "aesni_intel" "r8169"
        ];
        luks = {
            yubikeySupport = true;
            cryptoModules = [ "aes" "xts" "sha256" "sha512" "cbc" ];
                devices."encrypted" = {
                device = "/dev/nvme0n1p3";

                yubikey = {
                    slot = 2;
                    twoFactor = true;
                    gracePeriod = 30;
                    keyLength = 64;
                    saltLength = 16;

                    storage = {
                        device = "/dev/disk/by-label/EFI";
                        fsType = "vfat";
                        path = "/crypt-storage/default";
                    };
                };
            };
        };
    };
}