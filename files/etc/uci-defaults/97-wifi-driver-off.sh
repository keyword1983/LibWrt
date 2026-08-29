#!/bin/sh
# Keep wifi drivers compiled into the image, but don't bring radios up or
# load the kmods at boot, to save RAM on a 512MB device that's used as a
# wired-only gateway. Re-enabling later just needs LuCI + a reboot.

BOARD_NAME=$(cat /tmp/sysinfo/board_name 2>/dev/null || true)

# Only block Wi-Fi on Arthur (re-ss-01). Keep Wi-Fi enabled on Athena (re-cs-02 / re-cs-02-large) and other devices.
if [ "$BOARD_NAME" != "jdcloud,re-ss-01" ]; then
	exit 0
fi

for dev in $(uci show wireless 2>/dev/null | sed -n "s/^wireless\.\([^.]*\)=wifi-device$/\1/p"); do
	uci set wireless.$dev.disabled='1'
done
for ifc in $(uci show wireless 2>/dev/null | sed -n "s/^wireless\.\([^.]*\)=wifi-iface$/\1/p"); do
	uci set wireless.$ifc.disabled='1'
done
uci commit wireless

for f in /etc/modules.d/*ath11k* /etc/modules.d/*-mac80211 /etc/modules.d/*-cfg80211; do
	[ -e "$f" ] && mv "$f" "$f.disabled"
done

exit 0
