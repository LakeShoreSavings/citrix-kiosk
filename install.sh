#!/bin/bash

CHROOT_DIR=/opt/ltsp/amd64
MANAGED=/etc/chromium-browser/policies/managed
RECOMMENDED=/etc/chromium/-browser/policies/recommended
ERRLOG=/var/log/ltsp.error.log

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

if ! [ -x "$(command -v git)" ]; then
  echo "Git is not installed, installing... " 
  apt install -qq -y git >/dev/null 2>> $ERRLOG
fi

echo "Setting chroot to ${CHROOT_DIR}"

read -n 1 -s -r -p "Press any key to continue"

#Enable serial console in case hosted on KVM 
HV=$(dmesg | grep "Hypervisor detected" | awk '{print $5}')
if [ "$HV" == "KVM" ]; then
echo ""
echo "KVM Virtualization detected, adding serial port for virtual console."


cat > /lib/systemd/system/ttyS0.service <<EOF
[Unit]
Description=Serial Console Service

[Service]
ExecStart=/sbin/getty -L 115200 ttyS0 vt102
Restart=always

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /lib/systemd/system/ttyS0.service
systemctl daemon-reload > /dev/null 2>&1 
systemctl enable ttyS0.service > /dev/null 2>&1 
systemctl start ttyS0.service > /dev/null 2>&1 

fi

#update hosts file
sed -i "s/127.*/& ${HOSTNAME}/g" /etc/hosts
echo "200.50.1.104 influxdb.lakeshoresavings.local influxdb" >> /etc/hosts

#Pull our config files from the Git repo
echo ""
echo "Cloning Git Repo..."
git clone "https://github.com/bdelcamp/kiosk.git" "/opt/kiosk" > /dev/null 2>> "$ERRLOG"

if [ $? -ne 0 ]; then
  read -n 1 -s -r -p "Error cloning repo. Press any key to cleanup and exit"
  userdel kiosk
  rm -rf /opt/kiosk
  exit 1
fi

#Create our kiosk user & set defaults
echo "Create Kiosk user"
useradd -u 1001 -m kiosk
echo "kiosk:kiosk" | chpasswd


## allow reboot
cat > /etc/sudoers.d/kiosk << EOF
kiosk ALL=NOPASSWD:/sbin/reboot
EOF

chmod 0440 /etc/sudoers.d/kiosk


sudo -u kiosk mkdir -p \
"/home/kiosk/.config/openbox" \
"/home/kiosk/.local/share/applications" 

#create openbox autostart
cat > /home/kiosk/.config/openbox/autostart << EOF
#!/bin/bash

while :
do
  xset s off
  setterm -blank 0 -powersave off -powerdown 0
  rm -rf /tmp/kiosk
  rm -rf ~/Downloads/*
  rm -rf ~/.config/{chromium, cache} 
  
  mkdir -p /tmp/kiosk/  
  tar -C /tmp/kiosk/ -xvf /opt/kiosk/chromium.tar
  
  chromium-browser \
    --user-data-dir=/tmp/kiosk/chromium \
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

#strip down openbox menu
cat /opt/kiosk/menu.xml > /home/kiosk/.config/openbox/menu.xml

# read -n 1 -s -r -p "Press any key to continue"

echo "" 
echo -n "Bringing system packages up to date, this could take a while... "
#be new
apt update >/dev/null 2>&1 | tee -a "$ERRLOG"
DEBIAN_FRONTEND=noninteractive apt upgrade -y --force-yes >/dev/null 2>>"$ERRLOG"

#install pre-requisite packages
apt install  -y --no-install-recommends xdg-utils >/dev/null 2>>"$ERRLOG"

echo -n "done."

echo ""
echo "Installing LTSP Packages... "

#install ltsp-server packages 
add-apt-repository --yes ppa:ts.sch.gr >/dev/null 2>>/var/log/ltsp.error.log
apt update >/dev/null 2>>$ERRLOG
apt install -y ltsp-server-standalone >/dev/null 2>>$ERRLOG


if [ $? -ne 0 ]; then
    echo "Error installing LTSP Packages"
    exit 1
fi

echo -n "done"

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
HOSTNAME_BASE=LSSB
SOUND=True
VOLUME=100
X_BLANKING=False

EOF

# read -n 1 -s -r -p "Press any key to continue"

#Build initial chroot image
echo ""
echo -n "Bundling initial chroot..."


build_chroot () {
    ltsp-build-client --purge-chroot \
    --mount-package-cache \
    --extra-mirror 'http://ppa.launchpad.net/ts.sch.gr/ppa/ubuntu bionic main' \
    --apt-keys '/etc/apt/trusted.gpg.d/ts_sch_gr_ubuntu_ppa.gpg' > /dev/null 2>>/var/log/chroot.error.log
    if [ $? -ne 0 ]; then
        echo -n "ERROR ${?}"
        echo ""
        echo "*** Error creating chroot ***"
    fi
}

BUILD_ATTEMPT=1
while ! build_chroot; do
    ((BUILD_ATTEMPT+=1))
    echo "Build failed, retrying "
    echo -n "."
    sleep 1
done

echo ""
echo "Build succeeded on attempt $BUILD_ATTEMPT"



#Customize chroot image
echo "" 
echo -n "Customizing CHROOT"
echo "--Setting Timezone"
rm /etc/localtime && ln -s /usr/share/zoneinfo/America/New_York /etc/localtime
rm ${CHROOT_DIR}/etc/localtime; cp /usr/share/zoneinfo/America/New_York ${CHROOT_DIR}/etc/localtime

echo "--Installing Window Manager & Chromium"
ltsp-chroot -m --base /opt/ltsp --arch amd64 apt install -y openbox chromium-browser > /dev/null

echo "--Adding entries to hosts file"
cat > ${CHROOT_DIR}/etc/init.d/add-hosts <<EOF
echo "172.16.99.99 lssb-ctxddc01.lakeshoresavings.local lssb-ctxddc01" >> /etc/hosts
EOF

cat << EOF | chroot ${CHROOT_DIR}
chmod +x /etc/init.d/add-hosts
ln -s /etc/init.d/add-hosts /etc/rc2.d/S01add-hosts
EOF

#Copy Kiosk configs to chroot
echo ""
echo -n "--Establishing defaults"
cp -R /opt/kiosk/ ${CHROOT_DIR}/opt
chmod 655 ${CHROOT_DIR}/opt/kiosk/chromium.tar

#Create chromium policy folders & copy definitions
echo ""
echo -n "--Creating browser policies"
mkdir -p ${CHROOT_DIR}/${MANAGED} ${CHROOT_DIR}/${RECOMMENDED}
cp /opt/kiosk/managed/*.json ${CHROOT_DIR}/${MANAGED}


#install Citrix Receiver in chroot
echo ""
echo -n "--Installing Citrix Workspace in chroot"

cat << EOF | chroot "$CHROOT_DIR"
dpkg -i /opt/kiosk/icaclient_19.3.0.5_amd64.deb && apt-get install -f -qq
dpkg -i /opt/kiosk/ctxusb_2.7.5_amd64.deb && apt-get install -f -qq
if [ "$?" -ne 0 ]; then
echo "*** Error installing Citrix Workstation. Please install manually, then update chroot image ***"
fi
EOF


#set Citrix as default handler for session files
su - kiosk -c "xdg-mime default wfica.desktop application/x-ica"

#accept Citrix EULA
install -d -o 1001 -g 1001 /home/kiosk/.ICAClient
touch /home/kiosk/.ICAClient/.eula_accepted


#do postflight checks before updating image
ERROR=0

echo ""
echo "Performing preflight checks before updating image..."
if ! [ -f "$CHROOT_DIR/usr/bin/openbox" ]; then
  echo "Openbox did not get installed..."
  ((ERROR+=1))
fi

if ! [ -f "$CHROOT_DIR/usr/bin/chromium-browser" ]; then
  echo "Chromium did not get installed..."
  ((ERROR+=1))
fi

if [ "$ERROR" -ne 0 ]; then
  read -n 1 -s -r -p "Press any key to continue"
else
  echo "Validations complete. Total errors: $ERROR"
fi




#Finally, update customized netboot image
echo ""
echo -n "Finalizing boot image"
ltsp-update-sshkeys
ltsp-update-image > /dev/null 2>>/var/log/chroot.error.log
ltsp-config dnsmasq



#Install telegraf
echo ""
echo "Installing telegraf..."
curl -sL https://repos.influxdata.com/influxdb.key | apt-key add -
source /etc/lsb-release
echo "deb https://repos.influxdata.com/${DISTRIB_ID,,} ${DISTRIB_CODENAME} stable" | tee /etc/apt/sources.list.d/influxdb.list
apt update && apt -y -qq install telegraf
sleep 5
sed -i "97i urls = [\"http://influxdb:8086\"]\ndatabase = \"telegraf\" \n" /etc/telegraf/telegraf.conf


echo "Process complete!!"
read -n 1 -s -r -p " **Restart Required** Press any key to reboot..."
shutdown -r now
