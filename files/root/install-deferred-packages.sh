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

# Auto-configure Dnsmasq to forward DNS queries to AdGuard Home (127.0.0.1#55) with strict-order fallback (168.95.1.1, 8.8.8.8) once installed
if [ -x "/opt/bin/AdGuardHome" ] || [ -f "/etc/init.d/adguardhome" ]; then
	uci set dhcp.@dnsmasq[0].dns_forward_max='1000' 2>/dev/null || true
	uci set dhcp.@dnsmasq[0].strictorder='1' 2>/dev/null || true
	uci set dhcp.@dnsmasq[0].noresolv='1' 2>/dev/null || true
	uci set dhcp.@dnsmasq[0].addsubnet='32,128' 2>/dev/null || true
	uci set dhcp.@dnsmasq[0].addmac='1' 2>/dev/null || true
	uci del dhcp.@dnsmasq[0].server 2>/dev/null || true
	uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#55' 2>/dev/null || true
	uci add_list dhcp.@dnsmasq[0].server='168.95.1.1' 2>/dev/null || true
	uci add_list dhcp.@dnsmasq[0].server='8.8.8.8' 2>/dev/null || true
	uci commit dhcp 2>/dev/null || true
	/etc/init.d/dnsmasq restart 2>/dev/null || true

	# Inject optimized manga/app-recommendation ad blocking rules into AdGuard Home
	if [ -f "/etc/adguardhome/adguardhome.yaml" ]; then
		python3 - << 'EOF' 2>/dev/null || true
import re, os
config_path = "/etc/adguardhome/adguardhome.yaml"
if os.path.exists(config_path):
    with open(config_path, "r", encoding="utf-8") as f:
        content = f.read()
    new_filters = """filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt
    name: AdAway Default Blocklist
    id: 2
  - enabled: true
    url: https://anti-ad.net/easylist.txt
    name: anti-AD Filter (亞洲/台灣網頁廣告防護)
    id: 4
  - enabled: true
    url: https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/AWAvenue-Ads-Rule.txt
    name: AWAvenue 秋風廣告規則 (移動端開屏與應用推薦防護)
    id: 5
  - enabled: true
    url: https://raw.githubusercontent.com/jdlingyu/ad-wars/master/hosts
    name: 大聖淨網 (小說漫畫彈窗與推薦防護)
    id: 6
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt
    name: AdGuard Mobile Ads filter (移動設備廣告過濾)
    id: 7
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter (基礎防護)
    id: 8"""
    new_user_rules = """user_rules:
  - '||googleads.g.doubleclick.net^'
  - '||pagead2.googlesyndication.com^'
  - '||adservice.google.com^'
  - '||adservice.google.com.tw^'
  - '||mobileads.google.com^'
  - '||googleadservices.google.com^'
  - '||app-measurement.com^'
  - '||ad.xiaomi.com^'
  - '||ad1.xiaomi.com^'
  - '||tracking.miui.com^'
  - '||telemetry.mshome.net^'
  - '||pangle.io^'
  - '||tiktokpangle.us^'
  - '||byteoversea.com^'
  - '||pangolin-sdk-toutiao.com^'
  - '||pangolin-sdk-toutiao-b.com^'
  - '||tobapplog.com^'
  - '||pglstatp-toutiao.com^'
  - '||gdt.qq.com^'
  - '||e.qq.com^'
  - '||adkwai.com^'
  - '||exoclick.com^'
  - '||exosrv.com^'
  - '||popads.net^'
  - '||popcash.net^'
  - '||adsterra.com^'
  - '||clickadu.com^'
  - '||applvn.com^'
  - '||applovin.com^'
  - '||mintegral.com^'
  - '||ironsrc.com^'
  - '||unityads.unity3d.com^'
  - '||supersonicads.com^'
  - '||vungle.com^'
  - '||adjoe.zone^'
  - '||admob.com^'
  - '||ads.google.com^'
  - '||doubleclick.net^'
  - '||googleadservices.com^'
  - '||googlesyndication.com^'"""
    if 'filters:' in content:
        content = re.sub(r'filters:.*?(?=\nwhitelist_filters:)', new_filters, content, flags=re.DOTALL)
    if 'user_rules:' in content:
        content = re.sub(r'user_rules:.*?(?=\ndhcp:)', new_user_rules, content, flags=re.DOTALL)
    content = re.sub(r'cache_size: \d+', 'cache_size: 16777216', content)
    content = re.sub(r'cache_ttl_min: \d+', 'cache_ttl_min: 1800', content)
    content = re.sub(r'cache_optimistic: \w+', 'cache_optimistic: true', content)
    with open(config_path, "w", encoding="utf-8") as f:
        f.write(content)
EOF
		/etc/init.d/adguardhome restart 2>/dev/null || true
	fi
fi

echo "Done. luci-app-passwall2 / luci-app-adguardhome / luci-app-tailscale / ModemManager should now be visible in LuCI."
