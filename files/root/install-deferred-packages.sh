#!/bin/sh
# Run this manually (e.g. over SSH) once you've confirmed /overlay is on
# the big eMMC partition (`df -h /overlay` should show ~100+ GiB, not the
# ~30M factory sliver) and you're ready to install PassWall2, AdGuardHome,
# Tailscale, and ModemManager (+ their kmod deps). These were left out of
# the base image to keep it under the device's 60MB rootfs partition; the
# .apk files here are compiled against this exact build's kernel/toolchain,
# so there's no ABI mismatch risk like there would be pulling from the
# public immortalwrt feed.
#
# This is intentionally *not* automatic (not a uci-defaults script): fetching
# packages and running apk over the network is exactly the kind of thing
# that shouldn't run unattended during boot.

set -e

BOARD_NAME=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "jdcloud,re-ss-01")

case "$BOARD_NAME" in
	"jdcloud,re-cs-02")
		TAG_NAME="deferred-packages-jdc-re-cs-02"
		;;
	"jdcloud,re-cs-02-large")
		TAG_NAME="deferred-packages-jdc-re-cs-02-large"
		;;
	*)
		TAG_NAME="deferred-packages-jdc-ax1800pro"
		;;
esac

RELEASE_URL="https://github.com/keyword1983/LibWrt/releases/download/${TAG_NAME}/deferred-packages.tar.gz"
WORKDIR="/tmp/deferred-packages"

OVERLAY_SIZE_KB=$(df -k /overlay | awk 'NR==2 {print $2}')
if [ "$OVERLAY_SIZE_KB" -lt 1048576 ]; then
	echo "/overlay is still the small factory slice ($((OVERLAY_SIZE_KB / 1024)) MiB)." >&2
	echo "Move it to the eMMC partition first, reboot, and re-check 'df -h /overlay' before running this." >&2
	exit 1
fi

mkdir -p "$WORKDIR"
wget -O "$WORKDIR/deferred-packages.tar.gz" --timeout=30 "$RELEASE_URL"
tar -xzf "$WORKDIR/deferred-packages.tar.gz" -C "$WORKDIR"
apk add --allow-untrusted "$WORKDIR"/*.apk
rm -rf "$WORKDIR"

# Auto-configure Dnsmasq to forward all DNS queries to AdGuard Home (127.0.0.1#55) once installed
if [ -x "/opt/bin/AdGuardHome" ] || [ -f "/etc/init.d/adguardhome" ]; then
	uci del dhcp.@dnsmasq[0].server 2>/dev/null || true
	uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#55' 2>/dev/null || true
	uci set dhcp.@dnsmasq[0].noresolv='1' 2>/dev/null || true
	uci commit dhcp 2>/dev/null || true
	/etc/init.d/dnsmasq restart 2>/dev/null || true
fi

echo "Done. luci-app-passwall2 / luci-app-adguardhome / luci-app-tailscale / ModemManager should now be visible in LuCI."
