#!/usr/bin/env bash
# Source: https://linuxconfig.org/how-to-install-void-linux-with-lvm-on-luks-encryption

read -p "Enter drive: " DRIVENAME
read -p "Enter root size: " ROOTSIZE
read -p "Enter swap size: " SWAPSIZE
read -s -p "Enter luks password: " LUKSPASSWORD
echo ""
read -s -p "Enter root password: " ROOTPASSWORD
echo ""
read -p "Enter user name: " NEWUSERNAME
read -s -p "Enter user password: " USERPASSWORD
echo ""

checkExit() {
    if $?; then 
        read -p "Success: click to continue"; 
    else 
        echo "-----------------------------------"
        read -p "ERROR: click to continue"; 
        echo "-----------------------------------"
    fi
}

false
checkExit

# partition the disk
sfdisk $DRIVENAME << EOF
label: gpt 
,600MiB,U
,1GiB,L
,,L
EOF
checkExit




# create root with luks
echo -n "$LUKSPASSWORD" | cryptsetup luksFormat --hash=sha512 --key-size=512 --cipher=aes-xts-plain64 $DRIVENAME"3" -

echo -n "$LUKSPASSWORD" | cryptsetup luksOpen $DRIVENAME"3" cryptroot -
pvcreate /dev/mapper/cryptroot
vgcreate linuxconfig_vg /dev/mapper/cryptroot
GIGABITES="GiB"
lvcreate -n root_lv -L$ROOTSIZE$GIGABITES linuxconfig_vg
lvcreate -n swap_lv -L$SWAPSIZE$GIGABITES linuxconfig_vg
lvcreate -n home_lv -l+100%FREE linuxconfig_vg

# create efi partition
mkfs.fat -F32 $DRIVENAME"p1"

# create boot partition
mkfs.ext4 $DRIVENAME"p2"

# make the root and home patition
mkfs.ext4 /dev/linuxconfig_vg/root_lv
mkfs.ext4 /dev/linuxconfig_vg/home_lv

# make swap
mkswap /dev/linuxconfig_vg/swap_lv

mkdir /mnt/target && mount /dev/linuxconfig_vg/root_lv /mnt/target
mkdir /mnt/target/home && mount /dev/linuxconfig_vg/home_lv /mnt/target/home
mkdir /mnt/target/boot && mount $DRIVENAME"p2" /mnt/target/boot
mkdir /mnt/target/boot/efi && mount $DRIVENAME"p1" /mnt/target/boot/efi

mkdir /mnt/target/{dev,sys,proc}
mount --rbind /dev /mnt/target/dev 
mount --rbind /sys /mnt/target/sys 
mount --rbind /proc /mnt/target/proc

xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt/target base-system cryptsetup lvm2 grub-x86_64-efi

xgenfstab -U /mnt/target > /mnt/target/etc/fstab
xchroot /mnt/target

echo vpvoid > /etc/hostname

echo LANG=en_GB.UTF-8 > /etc/locale.conf
echo "en_GB.UTF-8 UTF-8" > /etc/default/libc-locales
xbps-reconfigure -f glibc-locales

ln -sf /usr/share/zoneinfo/Europe/Zurich /etc/localtime

echo "root:$ROOTPASSWORD" | chpasswd

useradd -m -s /bin/bash -G wheel,audio,video,floppy,cdrom,optical,kvm,xbuilder $NEWUSERNAME
echo "$NEWUSERNAME:$USERPASSWORD" | chpasswd

ROOTDISKUUID=blkid -o value -s UUID $DRIVENAME"3"
sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=4 rd.luks.uuid='$ROOTDISKUUID' rd.lvm.vg=linuxconfig_vg\"" /etc/default/grub
grub-install --target=x86_64-efi --efi-dir=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg
xbps-reconfigure -fa

