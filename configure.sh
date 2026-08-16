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

# let VNC clients log straight into the console (runner) session — it has Safari, wallpaper control and AppleEvents
sudo dscl . -passwd runner "$1"

# enable Remote Management with legacy VNC access
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -configure -allowAccessFor -allUsers -privs -all
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -configure -clientopts -setvnclegacy -vnclegacy yes

# obfuscated VNC password (legacy VNC uses first 8 chars only)
echo "$2" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' | sudo tee /Library/Preferences/com.apple.VNCSettings.txt

# start VNC agent
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -restart -agent -console
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate

# grant ScreenCapture permission to screensharingd (without it VNC clients get a black screen on macOS 12.1+)
for CLIENT in com.apple.screensharingd com.apple.ARDAgent; do
  sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,indirect_object_identifier_type,indirect_object_identifier,flags,last_modified) VALUES ('kTCCServiceScreenCapture','$CLIENT',1,2,4,1,0,'UNUSED',0,CAST(strftime('%s','now') AS INTEGER))"
done
sudo launchctl bootout system/com.apple.screensharing 2>/dev/null || true
sleep 2
sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -restart -agent

# colorful wallpaper so the desktop is visibly alive (black default looks like a broken black screen)
IMG=$(find "/System/Library/Desktop Pictures" -maxdepth 1 -name "*.heic" | head -1)
osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$IMG\"" || true

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
