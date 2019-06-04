CHROOT_DIR=/opt/ltsp/amd64
MANAGED=/etc/chromium-browser/policies/managed
RECOMMENDED=/etc/chromium/-browser/policies/recommended
#$CHROME_USER_DATA_DIR


if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

#Pull our config files from the Git repo
#git clone "https://github.com/bdelcamp/kiosk.git" "/opt/kiosk"

#Create our kiosk user & set defaults

useradd -u 1001 -m -p $(echo "kiosk" | openssl passwd -1 -stdin) -s /bin/false kiosk

## allow reboot
cat > /etc/sudoers.d/kiosk << EOF
kiosk ALL=NOPASSWD:/sbin/reboot
EOF

chmod 0440 /etc/sudoers.d/kiosk


sudo -u kiosk mkdir -p \
"/home/kiosk/.config/openbox" \
"/home/kiosk/.local/share/applications" 

cp /opt/kiosk/chromium.tar /home/kiosk/.config/
chmod 655 /home/kiosk/.config/chromium.tar


#create openbox autostart
cat > /home/kiosk/.config/openbox/autostart << EOF

#!/bin/bash

while :
do
  xset s off
  setterm -blank 0 -powersave off -powerdown 0
  rm -rf ~/Downloads/*
  rm -rf ~/.{config/chromium, cache} 
  
  tar -C ~/.config/ -xvf ~/.config/chromium.tar
  
  chromium-browser \
    --user-data-dir=/opt/kiosk/chromium-browser
    --no-first-run \
    --start-maximized \
    --window-position=0,0 \
    --disable \
    --disable-translate \
    --disable-infobars \
    --disable-suggestions-ui \
    --disable-save-password-bubble \
    --disable-session-crashed-bubble \
    --incognito \
    --kiosk "http://lssb-ctxddc01.lakeshoresavings.local/Citrix/StoreWeb/"
  sleep 5
done &
EOF


#install pre-requisite packages
apt install -y --no-install-recommends \
xdg-utils

#install ltsp-server packages 
add-apt-repository ppa:ts.sch.gr && apt update && apt install -y --no-install-recommends ltsp-server-standalone 

if [ $? -ne 0 ]; then
    echo "Error installing LTSP Packages"
    exit 1
fi


##Only for NFS Exported Homes
##echo “/home *(rw,sync,no_subtree_check)” >> /etc/exports
##exportfs -ra


#Create ltsp client config 
ltsp-config lts.conf

cat > /var/lib/tftpboot/ltsp/amd64/lts.conf <<EOF
[Default]
LDM_AUTOLOGIN=True
LDM_USERNAME=kiosk
LDM_PASSWORD=kiosk
LDM_FATCLIENT=True
LDM_DIRECTX=True
LDM_SESSION=openbox
USE_LOCAL_SWAP=True
RCFILE_01="/etc/rc2.d/S01add-hosts"

SOUND=True
VOLUME=100
X_BLANKING=False

EOF

#Build initial chroot image

ltsp-build-client --purge-chroot --mount-package-cache --extra-mirror 'http://ppa.launchpad.net/ts.sch.gr/ppa/ubuntu bionic main' --apt-keys '/etc/apt/trusted.gpg.d/ts_sch_gr_ubuntu_ppa.gpg'

if [ $? -ne 0 ]; then
    echo "Error in build process"
    exit 1
fi

#Customize chroot image

rm $CHROOT_DIR/etc/localtime; cp /usr/share/zoneinfo/America/New_York $CHROOT_DIR/etc/localtime

ltsp-chroot -m --base /opt/ltsp --arch amd64 apt install -y openbox chromium-browser 

cat > $CHROOT_DIR/etc/rc2.d/S01add-hosts <<EOF
echo "172.16.99.99 lssb-ctxddc01.lakeshoresavings.local lssb-ctxddc01" >> /etc/hosts
EOF


#Copy Kiosk configs to chroot
cp -R /opt/kiosk $CHROOT_DIR/opt/kiosk

#Create chromium policy folders & copy definitions
mkdir -p $CHROOT_DIR/$MANAGED $CHROOT_DIR/$RECOMMENDED
cp /opt/kiosk/managed/*.json $CHROOT_DIR/$MANAGED

#install Citrix Receiver in chroot
ltsp-chroot -m --base /opt/ltsp --arch amd64 dpkg -i /opt/kiosk/caclientWeb_19.3.0.5_amd64.deb

#set Citrix as default handler for session files




#Finally, update customized netboot image

ltsp-update-sshkeys && ltsp-update-image
ltsp-config dnsmasq

#Install telegraf
wget https://dl.influxdata.com/telegraf/releases/telegraf_1.10.4-1_amd64.deb
sudo dpkg -i telegraf_1.10.4-1_amd64.deb 
