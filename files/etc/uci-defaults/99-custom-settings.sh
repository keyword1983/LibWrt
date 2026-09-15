#!/bin/sh
# 99-custom-settings.sh - First boot initial configuration script for OpenWrt build

# 1. Enable IGMP Snooping and WAN metrics for mwan3 failover
uci set network.@device[0].igmp_snooping='1'
uci set network.wan.metric='1'
if uci get network.usb_wan >/dev/null 2>&1; then
    uci set network.usb_wan.metric='2'
fi
if uci get network.mm_wan >/dev/null 2>&1; then
    uci set network.mm_wan.metric='3'
fi
uci commit network

# 2. Add usb_wan and mm_wan to Firewall WAN zone
if [ -f /etc/config/firewall ]; then
    uci del_list firewall.@zone[1].network='usb_wan' 2>/dev/null
    uci del_list firewall.@zone[1].network='mm_wan' 2>/dev/null
    uci add_list firewall.@zone[1].network='usb_wan'
    uci add_list firewall.@zone[1].network='mm_wan'
    uci commit firewall
fi

# 3. CPU Frequency Tuning (schedutil governor: 864MHz to 1512MHz)
if [ -f /etc/config/cpufreq ]; then
    uci set cpufreq.@cpufreq[0].governor0='schedutil'
    uci set cpufreq.@cpufreq[0].minfreq0='864000'
    uci set cpufreq.@cpufreq[0].maxfreq0='1512000'
    uci commit cpufreq
    /etc/init.d/cpufreq enable 2>/dev/null
fi



# 4. zRAM Memory Compression Tuning (256MB, lzo-rle, swappiness=60)
if [ -f /etc/config/zram ]; then
    uci set zram.@zram[0].size='256'
    uci set zram.@zram[0].comp_alg='lzo-rle'
    uci commit zram
fi

# 5. Network Performance & Enterprise TCP Tuning
if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null; then
cat << "EOF" >> /etc/sysctl.conf
vm.swappiness=60
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_keepalive_time=30
net.ipv4.tcp_keepalive_intvl=5
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_mtu_probing=1
net.core.netdev_max_backlog=10000
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_synack_retries=2
net.core.optmem_max=204800
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rfc1337=1
EOF
fi
sysctl -p /etc/sysctl.conf 2>/dev/null

# 6. MiniDLNA Configuration (Port 8200, 180s Samsung TV SSDP notify)
if [ -f /etc/config/minidlna ]; then
    uci set minidlna.config.port='8200'
    uci set minidlna.config.enabled='1'
    uci set minidlna.config.notify_interval='180'
    uci commit minidlna
fi

# 7. Dropbear SSH Interface Unbind (Ensure LAN SSH access)
if [ -f /etc/config/dropbear ]; then
    uci set dropbear.@dropbear[0].Interface=''
    uci commit dropbear
fi

# 7. AdGuard Home Filter List Pre-baking (AWAvenue + DaSheng + AdGuard Mobile + anti-AD + AdGuard DNS + User Rules)
if [ -f /etc/adguardhome/adguardhome.yaml ]; then
    cat << "EOF" > /tmp/update_agh_filters.py
import re
import os

config_path = "/etc/adguardhome/adguardhome.yaml"
if not os.path.exists(config_path):
    exit(0)

try:
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
except Exception:
    pass
EOF
    python3 /tmp/update_agh_filters.py 2>/dev/null || true
    rm -f /tmp/update_agh_filters.py
    /etc/init.d/adguardhome restart 2>/dev/null || true
fi

# Configure CPU frequency scaling governor for Arthur (re-ss-01) and Athena (re-cs-02)
BOARD_NAME=$(cat /tmp/sysinfo/board_name 2>/dev/null || true)

# Arthur (JDC AX1800 Pro): 864MHz to 1.200GHz
if [ "$BOARD_NAME" = "jdcloud,re-ss-01" ]; then
    uci set cpufreq.cpufreq.governor0='schedutil' 2>/dev/null || true
    uci set cpufreq.cpufreq.minfreq0='864000' 2>/dev/null || true
    uci set cpufreq.cpufreq.maxfreq0='1200000' 2>/dev/null || true
    uci commit cpufreq 2>/dev/null || true
fi

# Athena (JDC AX6600): 864MHz to 1.800GHz
if [ "$BOARD_NAME" = "jdcloud,re-cs-02" ]; then
    uci set cpufreq.cpufreq.governor0='schedutil' 2>/dev/null || true
    uci set cpufreq.cpufreq.minfreq0='864000' 2>/dev/null || true
    uci set cpufreq.cpufreq.maxfreq0='1800000' 2>/dev/null || true
    uci commit cpufreq 2>/dev/null || true
fi

# Configure MiniDLNA media directories
uci del minidlna.config.media_dir 2>/dev/null || true
uci add_list minidlna.config.media_dir='V,/mnt/sda2/A' 2>/dev/null || true
uci add_list minidlna.config.media_dir='V,/mnt/sda2/BaiduNetdiskDownload' 2>/dev/null || true
uci commit minidlna 2>/dev/null || true

# Patch /etc/init.d/minidlna so every restart automatically carries -R incremental rescan parameter
sed -i 's/procd_append_param command -S -f/procd_append_param command -S -R -f/' /etc/init.d/minidlna 2>/dev/null || true

# Safe crontab scheduled reboot (stop services & umount -l /mnt/sda2 before reboot)
mkdir -p /etc/crontabs
echo '0 3 * * 1,3,5 /etc/init.d/minidlna stop 2>/dev/null; /etc/init.d/alist stop 2>/dev/null; /etc/init.d/filebrowser stop 2>/dev/null; sync; umount -l /mnt/sda2 2>/dev/null; reboot' > /etc/crontabs/root
/etc/init.d/cron restart 2>/dev/null || true

# Configure Dnsmasq to forward DNS queries to AdGuard Home (127.0.0.1#55) with strict-order fallback (168.95.1.1, 8.8.8.8) and high concurrency (1000)
if [ -x "/opt/bin/AdGuardHome" ] || [ -f "/etc/init.d/adguardhome" ]; then
	uci set dhcp.@dnsmasq[0].dns_forward_max='1000' 2>/dev/null || true
	uci set dhcp.@dnsmasq[0].strictorder='1' 2>/dev/null || true
	uci set dhcp.@dnsmasq[0].noresolv='1' 2>/dev/null || true
	uci del dhcp.@dnsmasq[0].server 2>/dev/null || true
	uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#55' 2>/dev/null || true
	uci add_list dhcp.@dnsmasq[0].server='168.95.1.1' 2>/dev/null || true
	uci add_list dhcp.@dnsmasq[0].server='8.8.8.8' 2>/dev/null || true
	uci commit dhcp 2>/dev/null || true
fi

# Static DHCP Host Bindings Helper (Match by MAC address to prevent duplicates)
bind_static_host() {
    local name="$1" mac="$2" ip="$3"
    if ! uci show dhcp | grep -i "$mac" >/dev/null 2>&1; then
        uci add dhcp host 2>/dev/null || true
        uci set dhcp.@host[-1].name="$name" 2>/dev/null || true
        uci set dhcp.@host[-1].ip="$ip" 2>/dev/null || true
        uci set dhcp.@host[-1].mac="$mac" 2>/dev/null || true
    else
        local sec=$(uci show dhcp | grep -i "$mac" | cut -d. -f1,2 | head -n 1)
        if [ -n "$sec" ]; then
            uci set ${sec}.name="$name" 2>/dev/null || true
            uci set ${sec}.ip="$ip" 2>/dev/null || true
        fi
    fi
}

bind_static_host "Samsung-Smart-M7" "64:07:f6:4f:80:7c" "192.168.1.238"
bind_static_host "iPad" "46:9b:9c:47:a8:cc" "192.168.1.201"
bind_static_host "Lenovo-Pad" "a8:96:09:fc:80:4e" "192.168.1.133"
bind_static_host "Nintendo-Switch" "ec:c4:0d:76:c7:98" "192.168.1.240"

# Setup Gaming (EF) & 4K Streaming (AF41) DSCP Rules in nftables
nft add table inet game_dscp_table 2>/dev/null || true
nft add chain inet game_dscp_table forward_dscp '{ type filter hook forward priority -150; }' 2>/dev/null || true
nft add set inet game_dscp_table streaming_af41_set '{ type ipv4_addr; flags timeout; timeout 1d; }' 2>/dev/null || true
nft flush chain inet game_dscp_table forward_dscp 2>/dev/null || true

nft add rule inet game_dscp_table forward_dscp udp dport '{ 3074, 3478-3481, 5000-6000, 8000-9000, 8572, 8801-8802, 9296-9308, 10000-20000, 45000-65535 }' ip dscp set ef 2>/dev/null || true
nft add rule inet game_dscp_table forward_dscp tcp dport 8200 ip dscp set af41 2>/dev/null || true
nft add rule inet game_dscp_table forward_dscp ip daddr @streaming_af41_set ip dscp set af41 2>/dev/null || true

# Bind Dnsmasq nftset for Netflix / YouTube / Disney+ CDN Domain Auto-Recognition
uci del_list dhcp.@dnsmasq[0].nftset='/netflix.com/nflxvideo.net/nflxso.net/googlevideo.com/youtube.com/disneyplus.com/bamgrid.com/4#inet#game_dscp_table#streaming_af41_set' 2>/dev/null || true
uci add_list dhcp.@dnsmasq[0].nftset='/netflix.com/nflxvideo.net/nflxso.net/googlevideo.com/youtube.com/disneyplus.com/bamgrid.com/4#inet#game_dscp_table#streaming_af41_set' 2>/dev/null || true

# Apply all network commits
uci commit dhcp 2>/dev/null || true
uci commit network

exit 0





