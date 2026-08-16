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

cat << "EOF" > /etc/rc.local
# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.

echo schedutil > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null
/etc/init.d/cpufreq enable 2>/dev/null
/etc/init.d/cpufreq start 2>/dev/null

exit 0
EOF
chmod +x /etc/rc.local

# 4. zRAM Memory Compression Tuning (256MB, lzo-rle, swappiness=60)
if [ -f /etc/config/zram ]; then
    uci set zram.@zram[0].size='256'
    uci set zram.@zram[0].comp_alg='lzo-rle'
    uci commit zram
fi

# 5. Network Performance & TCP BBR Tuning
cat << "EOF" >> /etc/sysctl.conf
vm.swappiness=60
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
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
EOF
    python3 /tmp/update_agh_filters.py 2>/dev/null
    rm -f /tmp/update_agh_filters.py
fi

# Apply all network commits
uci commit network

exit 0
