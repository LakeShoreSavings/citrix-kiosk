#!/bin/bash



# be new
apt-get update

# get software
apt-get install \
    unclutter \
    xorg \
    chromium \
    openbox \
    lightdm \
    locales \
    pulseaudio \
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




# create autostart
if [ -e "/home/kiosk/.config/openbox/autostart" ]; then
  mv /home/kiosk/.config/openbox/autostart /home/kiosk/.config/openbox/autostart.backup
fi
cat > /home/kiosk/.config/openbox/autostart << EOF

#!/bin/bash

#unclutter -idle 0.1 -grab -root &
##removed options
##--window-size=1024,768 \
##--incognito \

while :
do
  rm -rf ~/Downloads/*
  rm -rf ~/.{config/chromium, cache} 
  
  tar -C ~/.config/chromium -xvf ~/.config/chromium.tar
  
  chromium \
    --no-first-run \
    --start-maximized \
    --window-position=0,0 \
    
    --disable \
    --disable-translate \
    --disable-infobars \
    --disable-suggestions-service \
    --disable-save-password-bubble \
    --disable-session-crashed-bubble \
    
    --kiosk "http://lssb-ctxddc01.lakeshoresavings.local/Citrix/StoreWeb/"
  sleep 5
done &
EOF

#create master_preferences for chromium
mkdir -p /etc/opt/chrome/policies/{managed, recommended}
cp ./managed/*.json /etc/opt/chrome/policies/managed
# cat > /etc/opt/chrome/policies/managed/master_preferences.json << EOF
# {
#   "homepage": "http://lssb-ctxddc01.lakeshoresavings.local/Citrix/StoreWeb/",
#   "DownloadDirectory": "/tmp/dl",
#   "ExtensionInstallForceList":[
  
#   ],
#   "default_apps_install_state":3,
#    "download":{
#       "directory_upgrade":true,
#       "extensions_to_open":"ica"
#    },
# }
# EOF

chmod -R 655 /etc/opt/chrome/policies/

# install Citrix Workspace
wget http://wiki.lakeshoresavings.local/attachments/1 -O /tmp/icaclientWeb_19.3.0.5_amd64.deb
dpkg -i /tmp/icaclientWeb_19.3.0.5_amd64.deb

# set .ica files to always open automatically
su - kiosk -c "xdg-mime default wfica.desktop application/x-ica"

# squelch agreement dialog
mkdir -p /home/kiosk/.ICAClient
chown kiosk:kiosk /home/kiosk/.ICAClient
touch /home/kiosk/.ICAClient/.eula_accepted

# Hide GRUB
sed -i s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0\\nGRUB_TIMEOUT_STYLE=HIDDEN\\nGRUB_HIDDEN_TIMEOUT=0\\nGRUB_HIDDEN_TIMEOUT_QUIET=TRUE/ /etc/default/grub
update-grub



echo "Done!"
reboot
