#!/usr/bin/env bash
# Source: https://linuxconfig.org/how-to-install-void-linux-with-lvm-on-luks-encryption
# check also: https://codeberg.org/Le0xFF/VoidLinuxInstaller/src/branch/main/vli.sh

lsblk

read -p "Enter drive: " DRIVENAME
read -p "Enter hostname: " NEWHOSTNAME
read -p "Enter root size: " ROOTSIZE
read -p "Enter swap size: " SWAPSIZE
read -s -p "Enter luks password: " LUKSPASSWORD
echo ""
read -p "Enter normal user name: " NEWUSERNAME

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

echo "y" | xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt/target base-system cryptsetup lvm2 grub-x86_64-efi
checkExit "install base system"

xgenfstab -U /mnt/target > /mnt/target/etc/fstab
checkExit "copy fstab"

mkdir -p /mnt/target/etc/wpa_supplicant
cp /etc/wpa_supplicant/wpa_supplicant.conf /mnt/target/etc/wpa_supplicant
cp -r /root/pxl-void /mnt/target/tmp/

ROOTDISKUUID=$(blkid -o value -s UUID $PARTITION3)

cat << EOF | xchroot /mnt/target /bin/bash
echo $NEWHOSTNAME > /etc/hostname
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
echo "en_GB.UTF-8 UTF-8" > /etc/default/libc-locales
/mnt/target xbps-reconfigure -f glibc-locales
ln -sf /usr/share/zoneinfo/Europe/Zurich /etc/localtime
useradd -m -s /bin/bash -G wheel,audio,video,floppy,cdrom,optical,kvm,xbuilder $NEWUSERNAME
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 rd.luks.uuid='"$ROOTDISKUUID"' rd.lvm.vg=linuxconfig_vg"/' /etc/default/grub
grub-install --target=x86_64-efi --efi-dir=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg
xbps-reconfigure -fa
EOF

echo "Set new password for root"
xchroot /mnt/target passwd root
echo "Set new password for user $NEWUSERNAME"
xchroot /mnt/target passwd $NEWUSERNAME
