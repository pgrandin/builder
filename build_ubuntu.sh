image=ubuntu-4G.img
MYROOT=/mnt/ubuntu
qemu-img create $image 4G
loop=`losetup -v -f --show $image|cut -d'/' -f3`
parted -s -a optimal $image mklabel msdos -- mkpart primary ext4 1 -1
sleep 5
kpartx -av /dev/$loop
losetup -v -f --show /dev/mapper/${loop}p1
sleep 5
mkfs.ext4 -q /dev/mapper/${loop}p1
e2label /dev/mapper/${loop}p1 cloudimg-rootfs
mount /dev/mapper/${loop}p1 $MYROOT

pushd $MYROOT
tar xfz /var/pgn/ubuntu-12.04-server-cloudimg-amd64-root.tar.gz

