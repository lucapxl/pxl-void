#!/bin/bash

# Author lucapxl 
# Date  2025-11-12

######################
# Defining some variables needed during the installation
######################
USERDIR=$(echo "/home/$SUDO_USER")
TOOLSDIR=$(echo "$USERDIR/_tools")

######################
# Packages
######################
PACKAGES="firefox tldr blueman bash-completion vim foot fastfetch" # basic tools
PACKAGES=" $PACKAGES labwc wlroots xorg-server-xwayland"                  # labwc and Xwayland related
PACKAGES=" $PACKAGES Waybar swaylock wlogout wlopm chayang"               # main tools (bar, lock screen, logout menu, brightness manager, wallpaper manager))
PACKAGES=" $PACKAGES dbus elogind polkit-elogind gvfs gnome-keyring"      # keychain for KeePassXC, SSH keys and nextcloud
PACKAGES=" $PACKAGES fuzzel wget unzip"                                   # Menu for labwc
PACKAGES=" $PACKAGES wdisplays kanshi"                                    # Graphical monitor manager and profile manager
PACKAGES=" $PACKAGES dunst"                                               # Graphical Notification manager
PACKAGES=" $PACKAGES brightnessctl gammastep"                             # Brightness manager and gamma changer
PACKAGES=" $PACKAGES playerctl"                                           # Player buttons manager
PACKAGES=" $PACKAGES pavucontrol pulseaudio"                              # audio devices manager
PACKAGES=" $PACKAGES NetworkManager"                                      # network manager
PACKAGES=" $PACKAGES grim slurp swaybg"                                   # screenshot and region selection tools
PACKAGES=" $PACKAGES adwaita-icon-theme"                                  # icon package
PACKAGES=" $PACKAGES tuigreet greetd"                                     # login manager
PACKAGES=" $PACKAGES mesa-dri mesa-intel-dri intel-video-accel"           # login manager
PACKAGES=" $PACKAGES foot foot-terminfo pcmanfm nautilus galculator tar"  # terminal, file manager, flatpak caltulator and tar
PACKAGES=" $PACKAGES flatpak xdg-desktop-portal-gtk"                      # nextcloud and file manager plugin
PACKAGES=" $PACKAGES nextcloud-client tmux"                               # nextcloud and file manager plugin
PACKAGES=" $PACKAGES adwaita-fonts freefont-ttf font-inter font-awesome font-awesome5 font-awesome6" # fonts
PACKAGES=" $PACKAGES intel-ucode btop ncdu chrony tlp"  # other tweaks

######################
# Making sure the user running has root privileges
######################
if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo"
  exit
fi

if [[ -z "$SUDO_USER" ]]; then
  echo "Please run with sudo from your user, not from the root user directly"
  exit
fi

######################
# Output function
######################
function logMe {
    echo "=== [INFO] " $1
    sleep 3
}

######################
# Output function
######################
function logError {
    echo "=== [ERROR] " $1
    sleep 1
}


######################
# creating necessary folders
######################
logMe "Creating necessary folders"
mkdir -p $TOOLSDIR
mkdir -p $USERDIR/.config
mkdir -p $USERDIR/.themes/
cd $TOOLSDIR

######################
# adding aliases for xbps
######################
logMe "Adding xbps-* bash aliases"
grep -qi "alias xi=.*" $USERDIR/.bashrc || echo "alias xi='sudo xbps-install -S'" >> $USERDIR/.bashrc
grep -qi "alias xu=.*" $USERDIR/.bashrc || echo "alias xu='sudo xbps-install -Su'" >> $USERDIR/.bashrc
grep -qi "alias xs=.*" $USERDIR/.bashrc || echo "alias xs='sudo xbps-query -Rs'" >> $USERDIR/.bashrc

######################
# setting variables
######################
logMe "Setting variables"
echo "XDG_RUNTIME_DIR=/run/user/$(id -u)" >> $USERDIR/.pam_environment

######################
# Updating current system
######################
logMe "Updating current system"
sudo xbps-install -Suy

######################
# Installing nonfree repo
######################
logMe "Installing nonfree repo"
sudo xbps-install -Sy void-repo-nonfree


######################
# Installing necessary packages
######################
logMe "Installing necessary packages via xbps"
sudo xbps-install -Sy $PACKAGES

######################
# Installing flathub and flatpaks
######################
logMe "Installing Flathub"
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.keepassxc.KeePassXC -y
flatpak install flathub io.github.flattool.Warehouse -y
flatpak install flathub org.dupot.easyflatpak -y
flatpak install flathub com.visualstudio.code -y
flatpak install flathub org.xfce.mousepad -y

######################
# Download and apply config files
######################
logMe "applying config files"
cd $TOOLSDIR
git clone https://github.com/lucapxl/dotconfig.git
cd dotconfig/files
mkdir -p $USERDIR/.config/
cp -R $TOOLSDIR/dotconfig/files/config/* $USERDIR/.config/
mkdir -p $USERDIR/.themes/
cp -R $TOOLSDIR/dotconfig/files/themes/* $USERDIR/.themes/

######################
# recursively fix ownership for .config directory
######################
chown -R $SUDO_USER:$SUDO_USER $USERDIR

######################
# enabling greetd at start and switching target to graphical
######################
logMe "Configuring greetd/tuigreet login manager"
sed -i 's/^command.*/command = "tuigreet --cmd \x27dbus-run-session labwc\x27"/' /etc/greetd/config.toml

######################
# Installing nerdfonts
######################
logMe "Installing nerdfonts"
TEMP_DIR=$(mktemp -d)
wget -O "$TEMP_DIR/font.zip" "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/SourceCodePro.zip"
unzip "$TEMP_DIR/font.zip" -d "$TEMP_DIR"
mkdir -p /usr/share/fonts/SourceCodePro
mv "$TEMP_DIR"/*.{ttf,otf} /usr/share/fonts/SourceCodePro/
fc-cache -f -v
rm -rf "$TEMP_DIR"

######################
# adding user to correct groups
######################
logMe "Adding user to correct groups"
sudo usermod -aG storage $SUDO_USER
sudo usermod -aG network $SUDO_USER
sudo usermod -aG input $SUDO_USER

######################
# enabling automount of usb drives
######################
logMe "enabling automount of usb drives"
sudo cat >/etc/polkit-1/rules.d/50-udisks.rules <<EOL
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel")) {
        if (action.id.startsWith("org.freedesktop.udisks2.")) {
            return polkit.Result.YES;
        }
    }
});
EOL

######################
# Disabling wpa_supplicant and dhcpd services
######################
logMe "Disabling wpa_supplicant and dhcpd services"
sudo rm -rf /var/service/wpa_supplicant
sudo rm -rf /var/service/dhcpcd
sudo rm -rf /var/service/acpid

######################
# enabling Greetd, NetworkManager and dbus services
######################
logMe "Enabling NetworkManager and dbus services"
sudo ln -s /etc/sv/dbus /var/service/
sudo ln -s /etc/sv/NetworkManager /var/service/
sudo ln -s /etc/sv/greetd /var/service/
sudo ln -s /etc/sv/chronyd /var/service/
sudo ln -s /etc/sv/tlp /var/service/
sudo ln -s /etc/sv/polkitd /var/service/

######################
# all done, rebooting
######################
logMe "[DONE] Installation completed! remember to reconnect to your network with 'nmtui' please reboot your system"
read -p ""
