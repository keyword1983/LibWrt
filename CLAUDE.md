# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**This repo is public.** Never commit credentials, private keys, or real IP/hostnames for
anyone's personal infrastructure. Local-only connection details (dev VM, physical test router)
live in `LOCAL-DEV-NOTES.md`, which is gitignored — check there first if you need to reach the
live test environment for this project, and never copy its contents into anything committed.

## What this repo is

A LibWrt (OpenWrt/ImmortalWrt-derived, NSS-enabled) source tree, customized on the
`jdc-ax1800pro-custom` branch for a specific device: a **JDCloud AX1800 Pro** router
(device symbol `jdcloud_re-ss-01`, Qualcomm IPQ6000, 512MB RAM). `main-nss` is the
upstream-tracking branch; all of this project's work happens on `jdc-ax1800pro-custom`.

Unlike a typical "build orchestration" repo, this one *is* the actual OpenWrt source tree
(feeds, target/, package/, etc. all present) — building means running `make` directly in
this checkout, not cloning something else at CI time.

## Key files

- **`seed.config`** — the single source of truth for this device's package selection.
  Copied to `.config` then run through `make defconfig` (which fills in Kconfig-resolved
  dependencies) before every build. Heavily commented — each block explains *why* a
  package is there, not just what it is. Read the comments before changing anything; several
  entries exist specifically to work around bugs discovered the hard way (see "Known
  gotchas" below).
  - `=y` → baked into the base squashfs image.
  - `=m` → built and packaged, but deliberately left **out** of the base image ("deferred"),
    to keep the image under this device's 60MB rootfs partition. Never use `=n` for something
    you actually want available — `=n` skips building it entirely.
- **`diy-jdc.sh`** — run before `./scripts/feeds install -a`. Pulls in packages that aren't in
  the standard feeds (openwrt-passwall, luci-app-tailscale, luci-app-openvpn — sparse-checked-out
  from `openwrt/luci`'s `openwrt-23.05` branch since it was removed from `master`, plus two `sed`
  patches for bugs in that vendored package — see comments in the script) and iStore.
- **`files/`** — rootfs overlay baked into the base image. Notably `files/etc/init.d/openvpn` +
  `files/lib/functions/openvpn.sh`: this build's `openvpn-openssl` package ships no classic
  init script (modern OpenWrt manages OpenVPN via netifd instead), so these are vendored from
  `openwrt/packages` (pre-netifd-migration) to restore procd-managed multi-instance support —
  see "OpenVPN client" below for why.
- **`files/root/install-deferred-packages.sh`** — manual (not uci-defaults) script that
  downloads `deferred-packages.tar.gz` from the `deferred-packages-jdc-ax1800pro` GitHub Release
  and `apk add`s everything in it. This is how the `=m` packages actually get onto a freshly
  flashed device. Intentionally not automatic (don't want unattended network activity at boot).
- **`docs/JDC-AX1800PRO-USAGE.md`** — end-user-facing usage guide (flashing, per-feature
  how-tos, known limitations). Keep this in sync with actual behavior; it's the first thing to
  update when a feature's setup steps change.
- **`.github/workflows/jdc-ax1800pro.yml`** — `workflow_dispatch`-only CI. Full clean build
  (`HiGarfield/cachewrtbuild` for incremental cache), optionally publishes a firmware release
  (tag `jdc-ax1800pro-<date>-<time>`) and the apk repo (see below) when `upload_release=1`.

## Targeting a different device

This build targets one specific device (`jdcloud_re-ss-01`) out of several already defined in
the same `qualcommax/ipq60xx` target — switching to another one already-defined device is a
`seed.config` change, not a new port. Other devices sharing this target (from
`target/linux/qualcommax/image/ipq60xx.mk` — check that file for the current list, this is a
snapshot, not exhaustive):

| Device symbol | DEVICE_MODEL | SoC | Notes |
|---|---|---|---|
| `jdcloud_re-ss-01` | RE-SS-01 | ipq6000 | This build's target (marketed as "AX1800 Pro") |
| `jdcloud_re-cs-02` | RE-CS-02 | ipq6010 | Stock partition layout (6MB kernel), needs `ath11k-firmware-qcn9074` |
| `jdcloud_re-cs-02-large` | RE-CS-02 (Large) | ipq6010 | Community large partition layout (16MB kernel) for modified U-Boot/GPT |
| `jdcloud_re-cs-07` | RE-CS-07 | ipq6010 | Explicitly *excludes* ath11k/hostapd packages (see its `DEVICE_PACKAGES` — likely no built-in wifi, or a different wifi chip) |
| `redmi_ax5-jdcloud` | Redmi AX5 JDCloud | ipq6000 | Different vendor branding, same JDCloud firmware lineage |

These are **internal codenames** (`RE-SS-01` etc.), not retail/marketing names — this repo's
source has no mapping from a marketing name (e.g. a Chinese product nickname) to these codenames.
**Never guess that mapping and flash based on the guess** — flashing the wrong device profile's
image onto real hardware can brick it (wrong DTS, wrong partition layout, wrong radio calibration
data). Confirm the exact codename against the physical unit (label on the device, stock firmware's
own "about" page, or the seller's listing) before changing anything below.

To switch: in `seed.config`, replace all four device-selection lines with the new device's symbol
(keep the `=y` on all four, both target lines stay `qualcommax`/`ipq60xx` since these devices all
share that target):

```
CONFIG_TARGET_qualcommax=y
CONFIG_TARGET_qualcommax_ipq60xx=y
CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_<new-device-symbol>=y
CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_<new-device-symbol>=y
```

Then `cp seed.config .config && make defconfig` — Kconfig will auto-resolve that device's own
`DEVICE_PACKAGES` (radio calibration/firmware packages, wifi driver variants, etc. — see the
per-device `ipq60xx.mk` blocks) without needing to touch anything else in `seed.config`. If the
new device's SoC/wifi hardware genuinely differs (e.g. `ipq6010` vs this build's `ipq6000`, or
`jdcloud_re-cs-07`'s apparent lack of the ath11k stack), re-check every device-specific comment in
`seed.config` (the USB3/NSS/wifi-offload blocks especially) — they were written and tested against
`jdcloud_re-ss-01`'s specific hardware and may not all apply as-is.

To see the **full, current** device list for this target (not just the JDCloud-branded ones — this
target has many other devices too) rather than relying on a snapshot like the table above:

```sh
grep -n '^define Device/' target/linux/qualcommax/image/ipq60xx.mk
```

or interactively via `make menuconfig` → Target System → Qualcomm Atheros QCA/QCN (IPQ) 60xx/106xx
→ Target Profile.

## Two persistent apk distribution channels

Both are separate from the firmware image itself and both need to be understood together:

1. **`deferred-packages-jdc-ax1800pro` GitHub Release** — a single `deferred-packages.tar.gz`
   asset containing the `=m` packages + their non-generic deps, consumed by
   `install-deferred-packages.sh`. **Automated in CI workflow** — automatically generated from all built `.apk` packages during CI runs with `upload_release=1` and updated to both the release tag and `deferred-packages-jdc-ax1800pro`.
2. **`gh-pages` branch** (published at `https://keyword1983.github.io/LibWrt/`) — a real apk
   repository (`packages.adb` index files, generated via `apk mkndx`), addable to a router's
   `/etc/apk/repositories.d/customfeeds.list` for direct `apk update && apk add <name>` without
   manually collecting files. Two-tier structure, **do not merge these**:
   - `aarch64_cortex-a53/{base,luci,packages}/` — generic, kernel-independent packages. One
     shared copy, safe to overwrite wholesale on every publish.
   - `qualcommax/ipq60xx/<firmware-release-tag>/` — kernel modules. **kmod packages carry an
     internal dependency on the exact kernel package they were built against; apk will refuse
     to install a mismatched one rather than installing something broken** (confirmed safe by
     testing). Because a kmod's build and its matching firmware image always come from the same
     clean CI run, each kmod folder is tagged with that run's release tag and includes a
     `KERNEL.txt` explaining how to verify a match (`apk list --installed | grep '^kernel-'`).
     Never overwrite an older tag's kmod folder — old firmware still needs it.
   - The CI workflow's "Publish apk repo to gh-pages" step automates this correctly (uses `git
     worktree` to avoid disturbing the main checkout). If doing this manually on the dev VM,
     replicate the same separation.
   - Signing: `APK_SIGNING_KEY` GitHub Actions secret (private half) + committed `public-key.pem`
     (public half) — a **fixed** keypair, not regenerated per build/run, so trust is consistent
     across CI runs and the dev VM instead of needing `--allow-untrusted` forever.

## Feature status (as of this writing)

- **PassWall2 / AdGuardHome / Tailscale** — deferred (`=m`), working, documented in the usage
  guide.
- **OpenVPN client** (LuCI → VPN → OpenVPN) — working. Deliberately **not** using netifd's
  `proto=openvpn` for this (see "Known gotchas"); uses the classic `luci-app-openvpn` LuCI page
  (pulled via `diy-jdc.sh` from `openwrt/luci`'s `openwrt-23.05` branch, since upstream removed
  it after that) + the vendored classic init script. `CONFIG_OPENVPN_openssl_ENABLE_LZO=y` is
  required for compatibility with legacy (pre-2.4, net30-topology) servers that use comp-lzo
  wire framing — without it the client hard-rejects any compression directive at all, which
  looks like a connect-but-no-data-flows bug that has nothing to do with compression settings
  at first glance.
- **ModemManager (USB 4G/5G modems)** — deferred, working. Supports QMI, CDC-NCM, MBIM, RNDIS,
  and AT/serial modes + `usb-modeswitch` for mode-switching dongles. No dedicated LuCI app
  (upstream doesn't ship one); configured via Network → Interfaces → Protocol → ModemManager.
- **UPnP** (`miniupnpd-nftables` + `luci-app-upnp`) — baked into base image (`=y`), working.
- **mwan3** (WAN + USB 4G/5G failover) — added to `seed.config` (`=m`) but **not yet fully
  usable**: needs `kmod-ip6tables` + `kmod-ipt-ipset`, which this build's *currently deployed*
  kernel doesn't have (adding mwan3 to `seed.config` changed kernel-affecting Kconfig symbols,
  so a kernel rebuild is required — see "Pending work"). Installing the `mwan3`/`luci-app-mwan3`
  packages themselves is harmless and doesn't touch the existing WAN config; the kmod gap just
  means the failover functionality itself can't be configured yet.
- **Tailscale exit-node/subnet-router** — needs the full legacy xtables kmod set
  (`kmod-ipt-nat`, `kmod-ipt-conntrack[-extra/-label]`, `kmod-nf-conncount`) even on this
  nftables/firewall4 build, because tailscaled manages its own iptables-nft-compat rules. All
  baked into base image (`=y`).

## Known gotchas (each cost real debugging time — don't rediscover these)

- **netifd's `proto=openvpn` doesn't reliably win the default route** against an already-up
  `wan` interface on this build: the tunnel connects fine and `ubus call
  network.interface.<x> status` shows the route as applied, but it doesn't actually land in the
  kernel routing table (a real netifd bug class — confirmed by testing metric ordering,
  `defaultroute` options, etc.; none of it helped). This is *why* the OpenVPN client uses the
  classic init.d/procd path instead of the modern netifd-integrated one. If revisiting this,
  the right tool is **mwan3**'s own policy-routing layer (it doesn't rely on netifd's
  main-vs-default-table arbitration at all), not netifd directly — but see mwan3's current
  kernel-gap status above.
- **netifd only scans `/lib/netifd/proto/*.sh` once, at its own startup.** Installing a new
  proto-providing package (e.g. modemmanager) while netifd is already running means the new
  protocol won't appear anywhere (`ubus call network get_proto_handlers`, LuCI's protocol
  dropdown) until `/etc/init.d/network restart`. This is a one-time thing per fresh install, not
  a persistent issue — after a reboot it's fine.
- **`option enabled '0'` on a `network.<name>` interface does nothing.** The real netifd field
  is `option auto '0'`. Setting only `enabled` means any `/etc/init.d/network restart` (which
  happens for unrelated reasons too, e.g. the netifd-rescan workaround above) silently brings
  the interface back up.
- **apk transactions are atomic.** A multi-package `apk add` that fails partway rolls back
  *everything* — you'll see packages that appeared to install a moment earlier vanish. Install
  one at a time when debugging a dependency chain, or check the full dependency tree first.
- **apk installs can silently hang for a *long* time** on this 512MB device under memory
  pressure with no error and no visible progress — not a broken command, just needs the swap
  file (see `LOCAL-DEV-NOTES.md`) and patience. Always run installs detached with output
  redirected to a log file rather than waiting in the foreground.
- **Kernel-affecting Kconfig changes are easy to trigger by accident.** Adding a seemingly
  unrelated package to `seed.config` can pull in a kmod dependency that flips a
  previously-unset kernel Kconfig symbol, which changes the kernel package's build hash. Every
  already-built kmod's install then requires *that exact* kernel, not just the same
  `uname -r` version string. Check `apk list --installed | grep '^kernel-'` (full hash, not
  just the version number) before assuming two builds are ABI-compatible.
- **A `sysupgrade` wipes the overlay** except for `/etc/config/*` (always included) and
  whatever's explicitly listed in `/etc/sysupgrade.conf`. Non-UCI state that deferred packages
  create — `/etc/openvpn/` (client `.ovpn`/auth files, server pki), `/etc/adguardhome/` (the
  actual AdGuardHome config, not just its UCI stub), `/etc/tailscale/` (login state),
  `/etc/apk/repositories.d/` (custom repo config) — needs to be added to `/etc/sysupgrade.conf`
  manually before it'll survive a reflash+restore cycle.

## Pending work

- **Automate `deferred-packages.tar.gz` rebuilding in CI.** (Completed) CI workflow (`.github/workflows/jdc-ax1800pro.yml`) automatically packages all built `.apk` files into `deferred-packages.tar.gz` and publishes it to both the release tag and the `deferred-packages-jdc-ax1800pro` GitHub Release asset when `upload_release=1`.
- **mwan3 kernel gap.** Needs a full rebuild + reflash cycle (kmod-ip6tables/kmod-ipt-ipset
  require kernel changes) before the failover functionality is actually usable. Do this as a
  deliberate, backed-up maintenance window, not a quick add-on — see the sysupgrade-wipes-overlay
  gotcha above; back up first, including the `/etc/sysupgrade.conf` additions.
- **USB 4G/5G real-hardware test.** Everything's installed (ModemManager + all the kmod modes)
  but never tested against an actual physical USB modem — only verified that the daemon starts
  cleanly and `mmcli -L` correctly reports "no modems found" with nothing plugged in.
- **Restore remaining OpenVPN client profiles** (`cliffvpn`, `cliffvpn2`, `purevpnus2tcp`,
  `my-vpn.conf`) referenced in an old backup but whose actual `.ovpn`/cert content wasn't in that
  backup — deferred until the user provides the real files. There's also an unconfigured
  WireGuard profile (`purevpn`, full private key present) from the same backup that hasn't been
  brought over at all yet.
- **iStore** is installed (`luci-app-store=y`) but unvalidated — untested whether any of its
  catalog actually installs cleanly on this custom kernel/NSS build (third-party app-store
  catalogs are commonly built against generic/mainline kernels, not custom ones like this).
