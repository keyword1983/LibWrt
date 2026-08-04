#!/bin/bash
# Pull in the community packages that aren't in the immortalwrt feeds,
# for the jdcloud_re-ss-01 (JDCloud AX1800 Pro) custom build.
# Run from the repo root, before `./scripts/feeds install -a`.
set -e

rm -rf package/openwrt-passwall package/luci-app-passwall2 \
       package/app-store-ui package/istore-luci \
       package/luci-app-tailscale

git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/luci-app-passwall2
git clone --depth=1 https://github.com/asvow/luci-app-tailscale package/luci-app-tailscale

git clone --depth=1 https://github.com/linkease/istore-ui /tmp/istore-ui
mkdir -p package/app-store-ui
cp -r /tmp/istore-ui/app-store-ui/* package/app-store-ui/

git clone --depth=1 https://github.com/linkease/istore /tmp/istore
mkdir -p package/istore-luci
cp -r /tmp/istore/luci/* package/istore-luci/

rm -rf /tmp/istore-ui /tmp/istore
