{ config, pkgs, ... }: { }

# {

#   boot.loader.grub.enable = false;

#   fileSystems."/" = {
#     fsType = "tmpfs";
#     options = [ "mode=0755" ];
#     neededForBoot = true;
#   };

#   fileSystems."/nix/.ro-store" =
#     {
#       device = "192.168.23.130:/store";
#       fsType = "nfs4";
#       options = [ "ro" "rsize=32768" "wsize=32768" "noacl" "nolock" ];
#       neededForBoot = true;
#     };

#   fileSystems."/nix/.rw-store" =
#     {
#       device = "/dev/nbd0";
#       fsType = "ext2";
#       neededForBoot = true;
#     };

#   fileSystems."/nix/store" =
#     {
#       device = "overlay";
#       fsType = "overlay";
#       options = [
#         "rw" "relatime"
#         "default_permissions"
#         "lowerdir=/nix/.rw-store/lower"
#         "workdir=/nix/.rw-store/work"
#         "upperdir=/nix/.rw-store/upper"
#       ];
#       noCheck = true;
#       neededForBoot = true;
#     };

#   fileSystems."/tmp" = {
#     device = "/nix/.rw-store/tmp";
#     options = [ "bind" ];
#     noCheck = true;
#   };

#   boot.initrd.availableKernelModules = [ "nfsv4" "overlay" "nbd" ];

#   usb-gadget = {
#     enable = true;
#     initrdDHCP = true;
#   };

#   boot.initrd.nbd = {
#     enable = true;
#     devices = {
#       nbd0 = { hostname = "192.168.23.130"; port = "10809"; };
#     };
#     postCommands = ''
#       echo "Preparing RW store"
#       mkfs.ext2 /dev/nbd0
#       mkdir /scratch
#       mount /dev/nbd0 /scratch
#       mkdir -p 0755 /scratch/lower /scratch/upper /scratch/work /scratch/tmp
#       echo "Created mountpoints"
#       sync
#       umount /scratch
#     '';
#   };

# }
