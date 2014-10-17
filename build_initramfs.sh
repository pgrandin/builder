mkdir -p /usr/src/initramfs/{dev,bin,sbin,etc,root,proc,sys} 
cp -aL /bin/busybox /usr/src/initramfs/bin
cp init /usr/src/initramfs/init 
chmod +x /usr/src/initramfs/init 
find . -print0 | cpio -ov -0 --format=newc | gzip -9 > /var/pgn/nuc_export/initramfs-ng.cpio.gz
