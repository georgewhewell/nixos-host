TARGET=${1:-/dev/sdsss}

echo "Using the following files"
echo "Tow-Boot: $TOW_BOOT"
echo "RootFS ZST archive: $ROOTFS_ZST"
echo "Target storage: $TARGET"

ROOTFS="nixos-rock5b.img"

echo "Extracting the RootFS archive..."
unzstd "$ROOTFS_ZST" -o "$ROOTFS"
echo "Leaving it here after script execution, remove it manually"
realpath $ROOTFS

DD_CMD="dd if=$ROOTFS of=$TARGET status=progress"
echo "I'm going to execute the following command:"
echo "$DD_CMD"
echo "Do you want to continue? (y/n)"
read -r continue

if [ "$continue" != "${continue#[Yy]}" ] ;then
    echo "Flashing..."
    "${DD_CMD}"
else
    echo "Aborted..."
    return 127
fi

