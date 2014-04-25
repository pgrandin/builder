export MAKEOPTS="-j24"
emerge -qu fluxbox xorg-x11  x11-misc/slim xdm xterm xset unclutter x11vnc
emerge -qu bluez dev-vcs/git wpa_supplicant wireless-tools syslog-ng
emerge -qu cmake imagemagick gpsd tmux sudo ntp
emerge -qu xinput_calibrator alsa-utils
emerge -qu csync
emerge -q localepurge strace gdb
pushd /root
#git clone https://github.com/csawyerYumaed/pyOwnCloud.git
#pushd pyOwnCloud
#eselect python set python2.7
#python setup.py install
#popd
popd
pushd /etc/init.d
ln -s net.lo net.eth0
ln -s net.lo net.wlan0
rc-update add bluetooth
rc-update add rfcomm
rc-update add gpsd
rc-update add dbus
rc-update add net.eth0
rc-update add net.wlan0
useradd navit -G audio,wheel
echo "navit:navit" | chpasswd
emerge -q subversion
pushd /home/navit
svn co svn://svn.code.sf.net/p/navit/code/trunk/navit/ navit 
mkdir navit-bin
pushd navit-bin
cmake -DSAMPLE_MAP:BOOL=OFF -DBUILD_MAPTOOL:BOOL=OFF ../navit/
popd
