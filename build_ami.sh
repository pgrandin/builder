[ -f /usr/sbin/parted ] || emerge -q parted
[ -f /usr/sbin/mkfs.vfat ] || emerge -q dosfstools
[ -f /usr/sbin/nbd-client ] || emerge -q sys-block/nbd
[ -f /sbin/kpartx ] || emerge -q multipath-tools
[ -f /usr/bin/qemu-img ] || emerge -q app-emulation/qemu

modprobe nbd || exit 
num_cpu=`facter processorcount`

setup_virtdisk()
{
  qemu-img create $image 8G || exit 12
  losetup -v -f --show $image
  parted -s -a optimal $image mklabel msdos -- mkpart primary ext4 1 -1
  sleep 5
  kpartx -av /dev/loop0 || exit 12
  losetup -v -f --show /dev/mapper/loop0p1
  sleep 5
  mkfs.ext4 -q /dev/mapper/loop0p1 || exit 12
  mount /dev/mapper/loop0p1 $MYROOT || exit 12
}

image="/root/gentoo.img"

STAGEFILE="stage3-amd64-20161208.tar.bz2"
TAG="instance"
SOURCEDIR="/mnt/workspace"
MYROOT="/mnt/build-${TAG}-s4"

rm $SOURCEDIR/*.qcow2

[ -d $MYROOT  ] || mkdir $MYROOT
setup_virtdisk

http_proxy="" wget -c http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/${STAGEFILE} -O ${SOURCEDIR}/${STAGEFILE} || exit 3

pushd $MYROOT
tar xfjp ${SOURCEDIR}/${STAGEFILE}

cp /etc/resolv.conf etc/ 

cat >> etc/portage/make.conf << EOF
FEATURES="buildpkg getbinpkg"
EOF

mkdir usr/portage

mkdir  var/tmp/portage
mount -t tmpfs -o size=4G tmpfs var/tmp/
mount -t tmpfs -o size=2G tmpfs tmp/
mount -o bind /usr/portage usr/portage/
mount -t proc proc proc/
mount -o rbind /dev/ dev/
mount -o rbind /sys/ sys/

cat > stage2.sh << EOF
env-update
source /etc/profile
export PS1="(chroot) \$PS1"
emerge-webrsync

#eselect profile set default/linux/amd64/13.0/no-multilib
cp /usr/share/zoneinfo/America/New_York /etc/localtime
echo "America/New_York" > /etc/timezone
echo 'rc_nocolor="yes"' >> /etc/rc.conf

kversion="4.4.26"
emerge -q =gentoo-sources-\$kversion
pushd /usr/src/linux
wget https://raw.github.com/pgrandin/kernel-configs/master/kvm-kernel.config -O .config
#wget https://raw.githubusercontent.com/pgrandin/kernel-configs/33e2c132aa69a84f06746061562852fb6c57a16c/kvm-kernel.config -O .config
make -j$num_cpu && make modules_install
cp arch/x86_64/boot/bzImage /boot/gentoo-kvm
make clean
popd

echo "root:scrambled" | chpasswd

cat > /etc/fstab << FSOF
/dev/vda1 /         ext4    defaults,noatime,nodiratime,async  0 1
shm        /dev/shm  tmpfs   nodev,nosuid,noexec                0 0
none       /proc     proc    defaults                           0 0
none       /sys      sysfs   defaults                           0 0
FSOF

pushd /etc/init.d
ln -s net.lo net.eth0
rc-update add net.eth0 default
rc-update add sshd default
popd

mkdir -p /etc/portage/package.keywords
mkdir -p /etc/portage/package.use
echo '>=sys-libs/ncurses-6.0-r1 abi_x86_32' > /etc/portage/package.use/grub
emerge -q =grub-0.97-r16

emerge -q vim

mkdir -p /boot/grub/

cat > /boot/grub/menu.lst << GOF
serial -unit=0 -speed=115200
terminal -timeout=10 console serial

default 0
timeout 0

title GNU/Linux-Gentoo
root (hd0,0)
kernel (hd0,0)/boot/gentoo-kvm root=/dev/vda1 panic=10 console=tty0 console=ttyS0,115200n8
initrd /boot/initramfs-genkernel-x86_64-\${kversion}-gentoo
GOF

cat > /boot/grub/grub.cfg << GOF
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
terminal_input --append  serial
terminal_output --append serial
set timeout=1
play 480 440 1

set default=0
set timeout=5
set root='(hd0,0)'
menuentry "Gentoo" {
  linux (hd0,msdos1)/boot/gentoo-kvm root=/dev/vda1 panic=10 console=tty0 console=ttyS0,115200n8
  initrd (hd0,msdos1)/boot/initramfs-genkernel-x86_64-\${kversion}-gentoo
}
GOF

ln -s /dev/loop0 /dev/ami 
ln -s /dev/mapper/loop0p1 /dev/ami1 
[ -e /sbin/grub ] && grub --batch << GOF
device (hd0) /dev/ami
root (hd0,0)
setup (hd0)
quit
GOF

emerge -q genkernel
USE="-perl" emerge -q dev-vcs/git
pushd /usr/src/
git clone https://github.com/pgrandin/gentoo-cloud-initramfs.git
genkernel --initramfs-overlay=/usr/src/gentoo-cloud-initramfs/overlay --linuxrc=/usr/src/gentoo-cloud-initramfs/linuxrc --install initramfs
popd

emerge -q vixie-cron syslog-ng virt-what
rc-update add vixie-cron
rc-update add syslog-ng
EOF

chroot $MYROOT /bin/bash /stage2.sh
popd

rsync -vrtza $SOURCEDIR/files/ami/ $MYROOT/

pushd $MYROOT
for script in etc/local.d/*.setup; do
  chroot $MYROOT /bin/bash $script
done

umount -l proc dev sys tmp var/tmp usr/portage
popd

rm -R $MYROOT/var/cache/*

sync
d=`date -u +"%Y%m%d-%H%M"`
qemu-img convert $image -O qcow2 $SOURCEDIR/gentoo-${d}.qcow2
#rm $image

sync

source keystone.credentials

glance image-delete gentoo-${d} 
glance image-create --name gentoo-${d} --is-public true --container-format bare --disk-format qcow2  < gentoo-${d}.qcow2


