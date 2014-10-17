[ -f /usr/sbin/parted ] || emerge -q parted
[ -f /usr/sbin/mkfs.vfat ] || emerge -q dosfstools
[ -f /usr/sbin/nbd-client ] || emerge -q sys-block/nbd
[ -f /sbin/kpartx ] || emerge -q multipath-tools
[ -f /usr/bin/qemu-img ] || emerge -q app-emulation/qemu
[ -f /usr/bin/mksquashfs ] || emerge -q sys-fs/squashfs-tools
modprobe nbd 

control_c()
# run if user hits control-c
{
  echo -en "\n*** Ouch! Exiting ***\n"
  pushd $MYROOT
  umount -l proc dev sys tmp var/tmp usr/portage
  popd
  kill -9 $pid
  exit $?
}

setup_virtdisk()
{
qemu-img create $image 4G || exit 12
qemu-nbd $image &
pid=$!
sleep 1
nbd-client localhost 10809 /dev/nbd0
fdisk /dev/nbd0 << EOF
n
p
1

+256M
t
c
n
p
2


a
1
w
EOF
kpartx -av /dev/nbd0 || exit 12
mkfs.vfat /dev/mapper/nbd0p1 || exit 12
mkfs.ext4 /dev/mapper/nbd0p2 || exit 12
}

trap control_c SIGINT

TAG="nuc"
SOURCEDIR="/var/pgn"
IMAGEDIR="${SOURCEDIR}/images/"
MYROOT="/mnt/build-${TAG}-s4"
[ -d $MYROOT ] || mkdir $MYROOT

STAGEFILE="stage3-amd64-20140410.tar.bz2"
STAGE=3

image="sdcard.img"

# not using a loopback device anymore
# setup_virtdisk
# mount /dev/mapper/nbd0p2 $MYROOT

http_proxy="" wget -c http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/${STAGEFILE} -O ${IMAGEDIR}/${STAGEFILE} || exit 3
set -x
pushd ${IMAGEDIR}
STAGEFILE4=`ls -rt stage4-${TAG}-basic-*.tar.bz2 |tail -n1`
#STAGEFILE4=`ls -rt stage4-${TAG}-nvt*.tar.bz2 |tail -n1`
if [[ -z $STAGEFILE4 ]]; then
	echo "Building from stage3 [$STAGEFILE]"
else
	STAGEFILE=$STAGEFILE4
	echo "Building from stage4 [$STAGEFILE]"
	STAGE=4
fi
popd

pushd $MYROOT
tar xjpf ${IMAGEDIR}/${STAGEFILE}
mkdir usr/portage

if [[ $STAGE -eq 3 ]]; then
	mount -t tmpfs -o size=4G tmpfs var/tmp/
	mount -t tmpfs -o size=2G tmpfs tmp/
	mount -o bind /usr/portage usr/portage/
	mount -t proc proc proc/
	mount -o rbind /dev/ dev/
	mount -o rbind /sys/ sys/
	
	cp /etc/resolv.conf etc/
	
	cat > etc/portage/make.conf << EOF
CHOST="x86_64-pc-linux-gnu"
CFLAGS="-march=corei7 -O2 -pipe"
CXXFLAGS="\${CFLAGS}"
USE="bindist libkms python X png jpeg alsa usb svg -cups"
FEATURES="buildpkg getbinpkg"
PORTAGE_BINHOST="http://packages.kazer.org/${TAG}/"
PKGDIR="/usr/portage/packages/${TAG}/"
VIDEO_CARDS="intel"
EOF

	cat > perform_stage4.sh << EOF
export MAKEOPTS="-j24"
emerge -NDuq @world
emerge -qu vim dhcpcd usbutils unzip lsof gentoolkit
rc-update add sshd
echo "root:navit" | chpasswd

exit
EOF

	chroot . /bin/bash /perform_stage4.sh || exit -1
	umount -l proc dev sys tmp var/tmp usr/portage
	rm etc/resolv.conf
	rm perform_stage4.sh
	d=`date -u +"%Y%m%d-%H%M"`
	mksquashfs * ${IMAGEDIR}/stage4-${TAG}-basic-${d}.squashfs
	tar cjpf ${IMAGEDIR}/stage4-${TAG}-basic-${d}.tar.bz2 .
fi


mount -t tmpfs -o size=4G tmpfs var/tmp/
mount -t tmpfs -o size=2G tmpfs tmp/
mount -o bind /usr/portage usr/portage/
mount -t proc proc proc/
mount -o rbind /dev/ dev/
mount -o rbind /sys/ sys/
cp /etc/resolv.conf etc/

rsync -rtza ${SOURCEDIR}/files/common/ .
rsync -rtza ${SOURCEDIR}/files/${TAG}/ .
cat > perform_stage4-2.sh << EOF
echo "Building stage4"

cat >  /etc/locale.nopurge  << LOF
MANDELETE
SHOWFREEDSPACE
en
en_US.UTF-8
LOF
localepurge

echo 'PORTAGE_RSYNC_EXTRA_OPTS="--exclude-from=/etc/portage/rsync_excludes"' >> /etc/portage/make.conf

cat >  /boot/grub/menu.lst << GOF
default 0
timeout 7
splashimage=/boot/grub/splash.xpm.gz

title=LiveCD Gentoo
        kernel /boot/vmlinuz real_root=/dev/loop0 looptype=squashfs loop=/livecd.squashfs vga=ask initrd udev cdroot 
        initrd /boot/initrd
GOF

echo "Done building stage4"
exit
EOF
chroot . /bin/bash /perform_stage4-2.sh || exit -1
umount -l proc dev sys tmp var/tmp usr/portage
d=`date -u +"%Y%m%d-%H%M"`
time mksquashfs * ${IMAGEDIR}/livecd-${TAG}-nvt-${d}.squashfs
tar cjpf ${IMAGEDIR}/stage4-${TAG}-nvt-${d}.tar.bz2 .


umount $MYROOT
kill -9 $pid
