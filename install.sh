#!/usr/bin/env bash
# Source: https://linuxconfig.org/how-to-install-void-linux-with-lvm-on-luks-encryption
# check also: https://codeberg.org/Le0xFF/VoidLinuxInstaller/src/branch/main/vli.sh

clear
echo "Enter the name for the normal user"
echo ""
read -p "Username: " NEWUSERNAME

clear
echo "Chose an hostname for your system"
echo
read -p "Hostname: " NEWHOSTNAME

clear
lsblk
echo 
echo "select drive where to install the system. remember to add /dev/ to your drivename"
echo 
read -p "Drive: " DRIVENAME
echo
echo "The system will be partitioned for UEFI systems."
echo "Evreything (but /boot) will be encrypted with LUKS"
echo 
echo "Chose a size for the root "/" Partition and for the SWAP partition"
echo "/home will take the rest of the available space in the LUKS container"
echo "example: 20G"
echo
read -p "Size for /: " ROOTSIZE
read -p "Size for SWAP: " SWAPSIZE
read -s -p "Enter luks password: " LUKSPASSWORD

clear
echo "INSTALLATION SUMMARY"
echo
echo "Hostname:   $NEWHOSTNAME"
echo "Username:   $NEWUSERNAME"
echo "Drive:      $DRIVENAME"
echo "Size /:     $ROOTSIZE"
echo "Size SWAP:  $SWAPSIZE"
echo 
read -p "press any key to confirm or ctrl+c to exit installation" CONFIRMATION
exit

checkExit() {
    if [ $? -eq 1 ]; then 
        echo "-----------------------------------"
        echo "-----------------------------------"
        echo "ERROR: failed step: $1"
        read -p "click to continue"; 
        exit
    fi
}

# partition the disk
sfdisk $DRIVENAME << EOF
label: gpt 
,600MiB,U
,1GiB,L
,,L
EOF
checkExit "partitioning"

# set partitions
PARTITIONS=($(blkid -o device | sort | grep $DRIVENAME))
PARTITION1=${PARTITIONS[0]}
PARTITION2=${PARTITIONS[1]}
PARTITION3=${PARTITIONS[2]}

# create root with luks
echo -n "$LUKSPASSWORD" | cryptsetup luksFormat --hash=sha512 --key-size=512 --cipher=aes-xts-plain64 $PARTITION3 -
checkExit "create root with luks"

echo -n "$LUKSPASSWORD" | cryptsetup luksOpen $PARTITION3 cryptroot -
checkExit "opening luks drive"

pvcreate /dev/mapper/cryptroot
checkExit "create partition in crypt"

vgcreate linuxconfig_vg /dev/mapper/cryptroot
checkExit "create lvm in luks"

GIGABITES="GiB"
lvcreate -n root_lv -L$ROOTSIZE$GIGABITES linuxconfig_vg
checkExit "create partitions in cryp"
lvcreate -n swap_lv -L$SWAPSIZE$GIGABITES linuxconfig_vg
checkExit "create partitions in cryp"

lvcreate -n home_lv -l+100%FREE linuxconfig_vg
checkExit "create root partition"

# create efi partition
mkfs.fat -F32 $PARTITION1
checkExit "create efi partition"

# create boot partition
mkfs.ext4 $PARTITION2
checkExit "create boot partition"

# make the root and home patition
mkfs.ext4 /dev/linuxconfig_vg/root_lv
checkExit "format drives"
mkfs.ext4 /dev/linuxconfig_vg/home_lv
checkExit "format drives"

# make swap
mkswap /dev/linuxconfig_vg/swap_lv
checkExit "make swap"

swapon /dev/linuxconfig_vg/swap_lv
checkExit "activate swap"

mkdir /mnt/target && mount /dev/linuxconfig_vg/root_lv /mnt/target
checkExit "mount drives"
mkdir /mnt/target/home && mount /dev/linuxconfig_vg/home_lv /mnt/target/home
checkExit "mount drives"
mkdir /mnt/target/boot && mount $PARTITION2 /mnt/target/boot
checkExit "mount drives"
mkdir /mnt/target/boot/efi && mount $PARTITION1 /mnt/target/boot/efi
checkExit "mount drives"

mkdir /mnt/target/{dev,sys,proc}
checkExit "mount drives"
mount --rbind /dev /mnt/target/dev 
checkExit "mount drives"
mount --rbind /sys /mnt/target/sys 
checkExit "mount drives"
mount --rbind /proc /mnt/target/proc
checkExit "mount drives"

echo "y" | xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt/target base-system cryptsetup lvm2 grub-x86_64-efi NetworkManager
checkExit "install base system"

xgenfstab -U /mnt/target > /mnt/target/etc/fstab
checkExit "copy fstab"

mkdir -p /mnt/target/etc/wpa_supplicant
cp /etc/wpa_supplicant/wpa_supplicant.conf /mnt/target/etc/wpa_supplicant
cp -r /root/pxl-void /mnt/target/root/

ROOTDISKUUID=$(blkid -o value -s UUID $PARTITION3)

cat << EOF | xchroot /mnt/target /bin/bash
echo $NEWHOSTNAME > /etc/hostname
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
echo "en_GB.UTF-8 UTF-8" > /etc/default/libc-locales
ln -s /etc/sv/NetworkManager /var/service/
/mnt/target xbps-reconfigure -f glibc-locales
ln -sf /usr/share/zoneinfo/Europe/Zurich /etc/localtime
useradd -m -s /bin/bash -G wheel,audio,video,floppy,cdrom,optical,kvm,xbuilder $NEWUSERNAME
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 rd.luks.uuid='"$ROOTDISKUUID"' rd.lvm.vg=linuxconfig_vg"/' /etc/default/grub
grub-install --target=x86_64-efi --efi-dir=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg
xbps-reconfigure -fa
EOF

clear
echo "Set new password for root"
echo
xchroot /mnt/target passwd root

clear
echo "Set new password for user $NEWUSERNAME"
echo
xchroot /mnt/target passwd $NEWUSERNAME

clear
echo "Installation is done. you might want to reboot the system"
echo "After rebooting, remember to connect to your network using 'nmtui'"
