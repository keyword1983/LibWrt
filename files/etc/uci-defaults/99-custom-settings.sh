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

# 7. AdGuard Home Slim Filter List Pre-baking (anti-AD + OISD Small + AdGuard DNS)
if [ -f /etc/adguardhome/adguardhome.yaml ]; then
    cat << "EOF" > /tmp/update_agh_filters.py
import yaml

config_path = "/etc/adguardhome/adguardhome.yaml"
try:
    with open(config_path, "r") as f:
        cfg = yaml.safe_load(f)

    slim_filters = [
        {
            "enabled": True,
            "url": "https://anti-ad.net/easylist.txt",
            "name": "anti-AD Filter (亞洲/台灣網頁廣告防護)",
            "id": 1
        },
        {
            "enabled": True,
            "url": "https://small.oisd.nl",
            "name": "OISD Small (精準輕量黑名單)",
            "id": 2
        },
        {
            "enabled": True,
            "url": "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt",
            "name": "AdGuard DNS filter",
            "id": 3
        }
    ]

    cfg["filters"] = slim_filters

    with open(config_path, "w") as f:
        yaml.dump(cfg, f, default_flow_style=False, allow_unicode=True)
except Exception:
    pass
    (python3 /tmp/update_agh_filters.py && rm -f /tmp/update_agh_filters.py) &
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

# Safe crontab scheduled reboot (stop minidlna & umount /mnt/sda2 before reboot)
mkdir -p /etc/crontabs
echo '0 3 * * 1,3,5 /etc/init.d/minidlna stop && sync && umount /mnt/sda2 2>/dev/null && reboot' > /etc/crontabs/root
/etc/init.d/cron restart 2>/dev/null || true

# Configure Dnsmasq to forward DNS queries to AdGuard Home (127.0.0.1#55) ONLY if AdGuard Home is installed
if [ -x "/opt/bin/AdGuardHome" ] || [ -f "/etc/init.d/adguardhome" ]; then
	uci del dhcp.@dnsmasq[0].server 2>/dev/null || true
	uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#55' 2>/dev/null || true
	uci set dhcp.@dnsmasq[0].noresolv='1' 2>/dev/null || true
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
nft add rule inet game_dscp_table forward_dscp ip daddr 192.168.1.238 ip dscp set af41 2>/dev/null || true
nft add rule inet game_dscp_table forward_dscp tcp dport 8200 ip dscp set af41 2>/dev/null || true
nft add rule inet game_dscp_table forward_dscp ip daddr @streaming_af41_set ip dscp set af41 2>/dev/null || true

# Bind Dnsmasq nftset for Netflix / YouTube / Disney+ CDN Domain Auto-Recognition
uci del_list dhcp.@dnsmasq[0].nftset='/netflix.com/nflxvideo.net/nflxso.net/googlevideo.com/youtube.com/disneyplus.com/bamgrid.com/4#inet#game_dscp_table#streaming_af41_set' 2>/dev/null || true
uci add_list dhcp.@dnsmasq[0].nftset='/netflix.com/nflxvideo.net/nflxso.net/googlevideo.com/youtube.com/disneyplus.com/bamgrid.com/4#inet#game_dscp_table#streaming_af41_set' 2>/dev/null || true

# Apply all network commits
uci commit dhcp 2>/dev/null || true
uci commit network

exit 0





