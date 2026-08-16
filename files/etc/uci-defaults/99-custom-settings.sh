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

# 8. AdGuard Home Filter Slimming (anti-AD + OISD Small + AdGuard + AdAway)
if [ -f /etc/adguardhome/adguardhome.yaml ]; then
    python3 -c "
import yaml
path = '/etc/adguardhome/adguardhome.yaml'
try:
    cfg = yaml.safe_load(open(path))
    cfg['filters'] = [
        {'enabled': True, 'url': 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt', 'name': 'AdGuard DNS filter', 'id': 1},
        {'enabled': True, 'url': 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt', 'name': 'AdAway Default Blocklist', 'id': 2},
        {'enabled': True, 'url': 'https://small.oisd.nl', 'name': 'OISD Blocklist Small (Router Optimized)', 'id': 3},
        {'enabled': True, 'url': 'https://anti-ad.net/easylist.txt', 'name': 'anti-AD Filter (Taiwan/Asia Optimized)', 'id': 4}
    ]
    yaml.safe_dump(cfg, open(path, 'w'), sort_keys=False)
except Exception:
    pass
" 2>/dev/null
fi

# Apply all network commits
uci commit network

exit 0
