#!/usr/bin/env bash
# Source: https://linuxconfig.org/how-to-install-void-linux-with-lvm-on-luks-encryption

lsblk

read -p "Enter drive: " DRIVENAME
read -p "Enter hostname: " NEWHOSTNAME
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

# create root with luks
echo -n "$LUKSPASSWORD" | cryptsetup luksFormat --hash=sha512 --key-size=512 --cipher=aes-xts-plain64 $DRIVENAME"3" -
checkExit "create root with luks"

echo -n "$LUKSPASSWORD" | cryptsetup luksOpen $DRIVENAME"3" cryptroot -
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
mkfs.fat -F32 $DRIVENAME"1"
checkExit "create efi partition"

# create boot partition
mkfs.ext4 $DRIVENAME"2"
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
mkdir /mnt/target/boot && mount $DRIVENAME"2" /mnt/target/boot
checkExit "mount drives"
mkdir /mnt/target/boot/efi && mount $DRIVENAME"1" /mnt/target/boot/efi
checkExit "mount drives"

mkdir /mnt/target/{dev,sys,proc}
checkExit "mount drives"
mount --rbind /dev /mnt/target/dev 
checkExit "mount drives"
mount --rbind /sys /mnt/target/sys 
checkExit "mount drives"
mount --rbind /proc /mnt/target/proc
checkExit "mount drives"

xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt/target base-system cryptsetup lvm2 grub-x86_64-efi
checkExit "install base system"

xgenfstab -U /mnt/target > /mnt/target/etc/fstab
checkExit "copy fstab"

xchroot /mnt/target

echo $NEWHOSTNAME > /etc/hostname

echo LANG=en_GB.UTF-8 > /etc/locale.conf
echo "en_GB.UTF-8 UTF-8" > /etc/default/libc-locales
xbps-reconfigure -f glibc-locales

ln -sf /usr/share/zoneinfo/Europe/Zurich /etc/localtime
checkExit "change timezone"

echo "root:$ROOTPASSWORD" | chpasswd
checkExit "change root password"

useradd -m -s /bin/bash -G wheel,audio,video,floppy,cdrom,optical,kvm,xbuilder $NEWUSERNAME
checkExit "adding user"

echo "$NEWUSERNAME:$USERPASSWORD" | chpasswd
checkExit "change user password"

ROOTDISKUUID=blkid -o value -s UUID $DRIVENAME"3"
sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=4 rd.luks.uuid='$ROOTDISKUUID' rd.lvm.vg=linuxconfig_vg\"" /etc/default/grub
checkExit "change grub cmldline"

grub-install --target=x86_64-efi --efi-dir=/boot/efi
checkExit "install grub"

grub-mkconfig -o /boot/grub/grub.cfg
checkExit "configure grub"

xbps-reconfigure -fa
checkExit "reconfigure xbps"

