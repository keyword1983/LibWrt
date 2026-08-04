#!/bin/sh
# PassWall2, AdGuardHome, Tailscale, ModemManager (+ kmod deps) are left out
# of the base image to stay under the 60MB rootfs partition. Once the
# eMMC overlay is actually mounted (i.e. we have real space to install
# into, not the ~34MB factory sliver), fetch them from this repo's release
# and install locally -- these .apk files were compiled against this exact
# build's kernel/toolchain, so there's no ABI mismatch risk like there
# would be pulling from the public immortalwrt feed.

RELEASE_URL="https://github.com/keyword1983/LibWrt/releases/download/deferred-packages-jdc-ax1800pro/deferred-packages.tar.gz"
WORKDIR="/tmp/deferred-packages"

# uci-defaults semantics: exit 0 means "done, delete this script"; any
# non-zero exit means "not done yet, keep it and retry next boot." Every
# early-return below before the real install must use a non-zero exit,
# otherwise the framework deletes us before we ever get a chance to run
# again once the preconditions are actually met.

# Only proceed once /overlay is actually backed by the big eMMC partition,
# not the small factory-image rootfs_data slice. On first boot this is
# still the small slice -- the extroot switch-over only completes on the
# *next* reboot, so we intentionally retry until then.
OVERLAY_SIZE_KB=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $2}')
[ -n "$OVERLAY_SIZE_KB" ] || exit 1
[ "$OVERLAY_SIZE_KB" -gt 1048576 ] || exit 1   # require >1GiB

# Need working WAN to fetch the release; retry next boot if not up yet.
mkdir -p "$WORKDIR"
if ! wget -q -O "$WORKDIR/deferred-packages.tar.gz" "$RELEASE_URL"; then
	rm -rf "$WORKDIR"
	exit 1
fi

tar -xzf "$WORKDIR/deferred-packages.tar.gz" -C "$WORKDIR"
apk add --allow-untrusted "$WORKDIR"/*.apk
rm -rf "$WORKDIR"

exit 0
