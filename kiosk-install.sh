#!/bin/bash
MANAGED=/etc/chromium/policies/managed
RECOMMENDED=/etc/chromium/policies/recommended


# be new
apt-get update

# get software
# apt-get install \
apt install --no-install-recommends \
    unclutter \
    xorg \
    chromium \
    openbox \
    lightdm \
    locales \
    pulseaudio \
    fail2ban \
    git \
    sudo \
    -y

# dir
mkdir -p /home/kiosk/.config/openbox
mkdir -p /home/kiosk/.local/share/applications
cp ./chromium.tar /home/kiosk/.config/
chmod 655 /home/kiosk/.config/chromium.tar



# create group
groupadd kiosk

# create user if not exists
id -u kiosk &>/dev/null || useradd -m kiosk -g kiosk -s /bin/bash 
usermod -aG audio kiosk

# rights
chown -R kiosk:kiosk /home/kiosk

# remove virtual consoles
if [ -e "/etc/X11/xorg.conf" ]; then
  mv /etc/X11/xorg.conf /etc/X11/xorg.conf.backup
fi
cat > /etc/X11/xorg.conf << EOF
Section "ServerFlags"
    Option "DontVTSwitch" "true"
EndSection
EOF

# create config
if [ -e "/etc/lightdm/lightdm.conf" ]; then
  mv /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup
fi
cat > /etc/lightdm/lightdm.conf << EOF
[SeatDefaults]
autologin-user=kiosk
EOF

# allow reboot
cat > /etc/sudoers.d/kiosk << EOF
kiosk ALL=NOPASSWD:/sbin/reboot
EOF

chmod 0440 /etc/sudoers.d/kiosk


# create autostart
if [ -e "/home/kiosk/.config/openbox/autostart" ]; then
  mv /home/kiosk/.config/openbox/autostart /home/kiosk/.config/openbox/autostart.backup
fi
cat > /home/kiosk/.config/openbox/autostart << EOF

#!/bin/bash

#unclutter -idle 0.1 -grab -root &

while :
do
  xset s off
  setterm -blank 0 -powersave off -powerdown 0
  rm -rf ~/Downloads/*
  rm -rf ~/.{config/chromium, cache} 
  
  tar -C ~/.config/ -xvf ~/.config/chromium.tar
  
  chromium \
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

#create policies for chromium
mkdir -p $MANAGED $RECOMMENDED
cp ./managed/*.json $MANAGED


chmod -R 655 $MANAGED

# install Citrix Workspace
dpkg -i ./icaclientWeb_19.3.0.5_amd64.deb


# set .ica files to always open automatically
su - kiosk -c "xdg-mime default wfica.desktop application/x-ica"

# squelch agreement dialog
mkdir -p /home/kiosk/.ICAClient
chown kiosk:kiosk /home/kiosk/.ICAClient
touch /home/kiosk/.ICAClient/.eula_accepted


#disable sleep & hibernation
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target


#Hardening install

##set kiosk user shell
chsh -s /bin/false kiosk

if [ ! -d ~/.ssh ]; then mkdir ~/.ssh; fi
cat ./authorized_keys >> ~/.ssh/authorized_keys

# Configure OpenBox CTXMenu
cat ./menu.xml > /home/kiosk/.config/openbox/menu.xml

##Hide GRUB
sed -i s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0\\nGRUB_TIMEOUT_STYLE=HIDDEN\\nGRUB_HIDDEN_TIMEOUT=0\\nGRUB_HIDDEN_TIMEOUT_QUIET=TRUE/ /etc/default/grub
update-grub



echo "Done!"
reboot
