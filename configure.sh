#!/bin/bash
# configure.sh VNC_USER_PASSWORD VNC_PASSWORD

# disable spotlight indexing
sudo mdutil -i off -a

# backup account (not needed for login; legacy VNC password mirrors the console session)
sudo dscl . -create /Users/vncuser
sudo dscl . -create /Users/vncuser UserShell /bin/bash
sudo dscl . -create /Users/vncuser RealName "VNC User"
sudo dscl . -create /Users/vncuser UniqueID 1001
sudo dscl . -create /Users/vncuser PrimaryGroupID 80
sudo dscl . -create /Users/vncuser NFSHomeDirectory /Users/vncuser
sudo dscl . -passwd /Users/vncuser "$1"
sudo createhomedir -c -u vncuser > /dev/null

# never sleep the machine or display
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
nohup caffeinate -dis >/dev/null 2>&1 &
sudo defaults -currentHost write com.apple.screensaver idleTime 0

# TCC: grant ScreenCapture to screensharingd, otherwise VNC clients get a black framebuffer (macOS 12.1+)
for CLIENT in com.apple.screensharingd com.apple.ARDAgent; do
  sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,indirect_object_identifier_type,indirect_object_identifier,flags,last_modified) VALUES ('kTCCServiceScreenCapture','$CLIENT',1,2,4,1,0,'UNUSED',0,CAST(strftime('%s','now') AS INTEGER))"
done

# legacy VNC password auth: mirrors the console (runner) session, no separate login session
echo "$2" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' | sudo tee /Library/Preferences/com.apple.VNCSettings.txt > /dev/null

sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -configure -allowAccessFor -allUsers -privs -all
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -configure -clientopts -setvnclegacy -vnclegacy yes

# restart the daemon so TCC grants and legacy config take effect
sudo launchctl bootout system/com.apple.screensharing 2>/dev/null || true
sleep 2
sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -restart -agent

# re-assert legacy mode after the restart (it can get reset by bootstrap)
echo "$2" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' | sudo tee /Library/Preferences/com.apple.VNCSettings.txt > /dev/null
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -configure -clientopts -setvnclegacy -vnclegacy yes
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -restart -agent -console

# colorful wallpaper: the black default looks like a broken black screen
IMG=$(find "/System/Library/Desktop Pictures" -maxdepth 1 -name "*.heic" | head -1)
osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$IMG\"" || true
