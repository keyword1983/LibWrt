#!/bin/sh
# Run this manually over SSH once the router is up and stable. Moves
# /overlay from the tiny factory rootfs_data slice onto the large unused
# eMMC partition, following the community-validated procedure for this
# device family (JDCloud AX1800 Pro / 亚瑟):
#   https://blog.csdn.net/hbwxszj/article/details/141092607
#   umount /dev/mmcblk0pNN; mkfs.ext4 -F /dev/mmcblk0pNN
#   cp -r /overlay/* onto it; block detect > /etc/config/fstab;
#   redirect that partition's target to /overlay; disable the old one.
#
# This is intentionally *not* automatic -- filesystem migrations like this
# should be watched, not run unattended during boot.

set -e

command -v block >/dev/null 2>&1 || { echo "block command not found" >&2; exit 1; }

ROOTPART=$(block info 2>/dev/null | awk -F: '/MOUNT="\/rom"/{print $1}')
BOOTDISK=$(echo "$ROOTPART" | sed -n 's/\(\/dev\/mmcblk[0-9]\+\)p[0-9]\+/\1/p')
[ -n "$BOOTDISK" ] || { echo "couldn't determine boot disk" >&2; exit 1; }

BEST=""
BESTSIZE=0
for part in "${BOOTDISK}"p*; do
	[ -b "$part" ] || continue
	case "$part" in *boot0|*boot1) continue ;; esac

	info=$(block info "$part" 2>/dev/null)
	fstype=$(echo "$info" | sed -n 's/.*TYPE="\([a-zA-Z0-9]*\)".*/\1/p')
	[ "$fstype" = "ext4" ] || continue

	mnt=$(echo "$info" | sed -n 's/.*MOUNT="\([^"]*\)".*/\1/p')
	case "$mnt" in ""|/overlay) ;; *) continue ;; esac

	base=$(basename "$part")
	size=$(cat "/sys/class/block/$base/size" 2>/dev/null)
	[ -n "$size" ] || continue

	if [ "$size" -gt "$BESTSIZE" ]; then
		BESTSIZE=$size
		BEST=$part
	fi
done

[ -n "$BEST" ] || { echo "no candidate partition found" >&2; exit 1; }
# require >1GiB (size is in 512B sectors)
[ "$BESTSIZE" -gt 2097152 ] || { echo "largest candidate ($BEST) is under 1GiB, aborting" >&2; exit 1; }

echo "Using $BEST ($((BESTSIZE / 2097152)) GiB) as the new /overlay."
read -p "Continue? This reformats $BEST. [y/N] " CONFIRM
case "$CONFIRM" in y|Y) ;; *) echo "aborted"; exit 1 ;; esac

BASE=$(basename "$BEST")
MNTPOINT="/mnt/$BASE"

mountpoint -q "$MNTPOINT" 2>/dev/null && umount "$MNTPOINT"

echo "Formatting $BEST (this can take a few minutes on a large partition)..."
mkfs.ext4 -F "$BEST"

mkdir -p "$MNTPOINT"
mount "$BEST" "$MNTPOINT"

echo "Copying current /overlay onto $BEST..."
cp -r /overlay/* "$MNTPOINT/" 2>/dev/null || true
ls "$MNTPOINT"

umount "$MNTPOINT"

echo "Regenerating /etc/config/fstab from the current block device state..."
block detect > /etc/config/fstab

# `block detect` writes a generic /mnt/<dev> target for our partition, and
# separately auto-detects the *current* rootfs_data device (whatever's
# still mounted at /overlay right now) with target=/overlay, enabled=1.
# Point our partition's entry at /overlay instead, and disable the old
# rootfs_data entry so there's only one active /overlay target.
uci show fstab | grep "\.target='/overlay'" | cut -d. -f1-2 | while read -r sect; do
	uci set "${sect}.enabled=0"
done

SECTION=$(uci show fstab | grep "=mount$" | cut -d. -f1-2 | while read -r s; do
	dev=$(uci -q get "${s}.uuid" 2>/dev/null)
	blk_uuid=$(block info "$BEST" 2>/dev/null | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
	[ "$dev" = "$blk_uuid" ] && echo "$s" && break
done)

if [ -n "$SECTION" ]; then
	uci set "${SECTION}.target=/overlay"
	uci set "${SECTION}.enabled=1"
	uci commit fstab
	echo "fstab updated. Reboot to switch over: reboot"
else
	echo "couldn't find the new partition's fstab section to redirect -- check /etc/config/fstab manually" >&2
	exit 1
fi
