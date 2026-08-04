#!/bin/sh
# Default to TCP BBR congestion control (helps PassWall2/SSR-Plus/OpenVPN
# throughput on high-latency links).

grep -q '^net.core.default_qdisc=fq$' /etc/sysctl.conf 2>/dev/null || \
	echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
grep -q '^net.ipv4.tcp_congestion_control=bbr$' /etc/sysctl.conf 2>/dev/null || \
	echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf

exit 0
