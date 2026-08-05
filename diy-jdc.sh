#!/bin/bash
# Pull in the community packages that aren't in the immortalwrt feeds,
# for the jdcloud_re-ss-01 (JDCloud AX1800 Pro) custom build.
# Run from the repo root, before `./scripts/feeds install -a`.
set -e

rm -rf package/openwrt-passwall package/luci-app-passwall2 \
       package/app-store-ui package/istore-luci \
       package/luci-app-tailscale package/luci-app-openvpn

git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/luci-app-passwall2
git clone --depth=1 https://github.com/asvow/luci-app-tailscale package/luci-app-tailscale

# Classic combined client+server OpenVPN LuCI page (admin/vpn/openvpn), removed
# from openwrt/luci master after the openwrt-23.05 branch point in favor of
# netifd-only integration (luci-app-openvpn-server only covers the server
# wizard). Pulled from the last branch that still has it via sparse-checkout,
# since openwrt/luci is a monorepo. Needs files/etc/init.d/openvpn +
# files/lib/functions/openvpn.sh (vendored separately in this repo) to
# actually start/stop instances -- this build's openvpn-openssl package
# doesn't ship those itself (modern OpenWrt manages openvpn via netifd
# instead, which doesn't reliably become the default route -- see commit
# history / session notes for why we're not using that path for the client).
git clone --depth=1 --branch openwrt-23.05 --filter=blob:none --sparse https://github.com/openwrt/luci /tmp/luci-openvpn-src
git -C /tmp/luci-openvpn-src sparse-checkout set applications/luci-app-openvpn
mkdir -p package/luci-app-openvpn
cp -r /tmp/luci-openvpn-src/applications/luci-app-openvpn/* package/luci-app-openvpn/
rm -rf /tmp/luci-openvpn-src

git clone --depth=1 https://github.com/linkease/istore-ui /tmp/istore-ui
mkdir -p package/app-store-ui
cp -r /tmp/istore-ui/app-store-ui/* package/app-store-ui/

git clone --depth=1 https://github.com/linkease/istore /tmp/istore
mkdir -p package/istore-luci
cp -r /tmp/istore/luci/* package/istore-luci/

rm -rf /tmp/istore-ui /tmp/istore
