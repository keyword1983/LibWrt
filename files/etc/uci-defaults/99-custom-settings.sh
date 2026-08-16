#!/bin/sh
# 99-custom-settings.sh - First boot initial configuration script for OpenWrt build

# 1. Enable IGMP Snooping on br-lan for multicast and game streaming optimization
uci set network.@device[0].igmp_snooping='1'
uci commit network

# 2. CPU Frequency Tuning (schedutil governor: 864MHz to 1512MHz)
if [ -f /etc/config/cpufreq ]; then
    uci set cpufreq.@cpufreq[0].governor0='schedutil'
    uci set cpufreq.@cpufreq[0].minfreq0='864000'
    uci set cpufreq.@cpufreq[0].maxfreq0='1512000'
    uci commit cpufreq
fi

# 3. zRAM Memory Compression Tuning (256MB, lzo-rle, swappiness=60)
if [ -f /etc/config/zram ]; then
    uci set zram.@zram[0].size='256'
    uci set zram.@zram[0].comp_alg='lzo-rle'
    uci commit zram
fi

if grep -q "vm.swappiness" /etc/sysctl.conf; then
    sed -i 's/vm.swappiness=.*/vm.swappiness=60/' /etc/sysctl.conf
else
    echo "vm.swappiness=60" >> /etc/sysctl.conf
fi

# 4. MiniDLNA Configuration (Port 8200, 180s Samsung TV SSDP notify)
if [ -f /etc/config/minidlna ]; then
    uci set minidlna.config.port='8200'
    uci set minidlna.config.enabled='1'
    uci set minidlna.config.notify_interval='180'
    uci commit minidlna
fi

# 5. Dropbear SSH Interface Unbind (Ensure LAN SSH access)
if [ -f /etc/config/dropbear ]; then
    uci set dropbear.@dropbear[0].Interface=''
    uci commit dropbear
fi

# 6. AdGuard Home Filter Slimming (anti-AD + OISD Small + AdGuard + AdAway)
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

exit 0
