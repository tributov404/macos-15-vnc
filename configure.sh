#!/bin/bash
# configure.sh VNC_USER_PASSWORD VNC_PASSWORD

# disable spotlight indexing
sudo mdutil -i off -a

# create login user
sudo dscl . -create /Users/vncuser
sudo dscl . -create /Users/vncuser UserShell /bin/bash
sudo dscl . -create /Users/vncuser RealName "VNC User"
sudo dscl . -create /Users/vncuser UniqueID 1001
sudo dscl . -create /Users/vncuser PrimaryGroupID 80
sudo dscl . -create /Users/vncuser NFSHomeDirectory /Users/vncuser
sudo dscl . -passwd /Users/vncuser "$1"
sudo createhomedir -c -u vncuser > /dev/null

# enable Remote Management with legacy VNC access
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -configure -allowAccessFor -allUsers -privs -all
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -configure -clientopts -setvnclegacy -vnclegacy yes

# obfuscated VNC password (legacy VNC uses first 8 chars only)
echo "$2" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' | sudo tee /Library/Preferences/com.apple.VNCSettings.txt

# start VNC agent
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -restart -agent -console
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate

# never sleep the machine or display
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
nohup caffeinate -dis >/dev/null 2>&1 &
sudo defaults -currentHost write com.apple.screensaver idleTime 0

# enable autologin for vncuser (kcpassword magic XOR encoding)
VNC_PW="$1" python3 - <<'EOF'
import os
pw = os.environ['VNC_PW']
key = [125, 137, 82, 35, 210, 188, 221, 234, 236, 95, 78, 56]
enc = bytearray(ord(c) ^ key[i % 12] for i, c in enumerate(pw))
while len(enc) % 12 != 0 or len(enc) == len(pw):
    enc.append(key[len(enc) % 12])
open('/tmp/kcpassword', 'wb').write(bytes(enc))
EOF
sudo cp /tmp/kcpassword /etc/kcpassword
sudo chown root:wheel /etc/kcpassword
sudo chmod 600 /etc/kcpassword
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser vncuser
