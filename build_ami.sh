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

STAGEFILE="stage3-amd64-nomultilib-20140213.tar.bz2"
STAGEFILE="stage3-amd64-20140410.tar.bz2"
TAG="instance"
SOURCEDIR="/var/pgn"
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

#eselect profile set default/linux/amd64/13.0/no-multilib
cp /usr/share/zoneinfo/America/New_York /etc/localtime
echo "America/New_York" > /etc/timezone
echo 'rc_nocolor="yes"' >> /etc/rc.conf

emerge -q =gentoo-sources-3.10.17
pushd /usr/src/linux
wget https://raw.github.com/pgrandin/kernel-configs/master/kvm-kernel.config -O .config
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
echo "=sys-boot/grub-0.97-r13 ~amd64" >> /etc/portage/package.keywords/grub
emerge -q =grub-0.97-r13
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
initrd /boot/initramfs-genkernel-x86_64-3.10.17-gentoo
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
  initrd (hd0,msdos1)/boot/initramfs-genkernel-x86_64-3.10.17-gentoo
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
pushd /root
git clone https://github.com/pgrandin/gentoo-cloud-initramfs.git
genkernel --initramfs-overlay=/root/gentoo-cloud-initramfs/overlay --linuxrc=/root/gentoo-cloud-initramfs/linuxrc --install initramfs
popd
EOF

chroot $MYROOT /bin/bash /stage2.sh
popd
rsync -rtza files/ami/ $MYROOT/

cat > $MYROOT/setup_OS.sh << EOF
emerge -q layman eix
cat >> /etc/portage/make.conf << POF
source /var/lib/layman/make.conf 
POF
wget https://raw.github.com/pgrandin/openstack-overlay/master/openstack-overlay.xml -O /etc/layman/overlays/openstack-overlay.xml
layman -L
layman -a openstack
eix-update
emerge -q tmux
#emerge -q =nova-2013.2-r1
EOF

chroot $MYROOT /bin/bash /setup_OS.sh


pushd $MYROOT
umount -l proc dev sys tmp var/tmp usr/portage
popd

rm -R $MYROOT/var/cache/*
rm $MYROOT/root/.bash_history
rm $MYROOT/root/.known_hosts
rm -R $MYROOT/root/.config/
rm $MYROOT/etc/ssh/ssh_host_*

d=`date -u +"%Y%m%d-%H%M"`
qemu-img convert $image -O qcow2 /var/pgn/gentoo-${d}.qcow2
#rm $image

sync
echo "All good! :) You can run 'build.sh gentoo-${d}' on the controller."

