# JDCloud AX1800 Pro (jdc-ax1800pro-custom) 使用教學

適用分支：`jdc-ax1800pro-custom`
裝置：JDCloud AX1800 Pro（`jdcloud_re-ss-01`，IPQ6000，512MB RAM）
預設登入：`192.168.1.1`，帳號 `root`，密碼 `password`

---

## 1. 刷機

前往 [Releases](https://github.com/keyword1983/LibWrt/releases) 找最新的 `jdc-ax1800pro-<日期>-<時間>` 版本：

- **從原廠韌體刷**：用 `-squashfs-factory.bin`
- **已經在跑這個客製韌體、要升級**：用 `-squashfs-sysupgrade.bin`（LuCI 的 System → Backup/Flash Firmware 頁面直接上傳即可）

刷完後預設會登入 `192.168.1.1`，帳號 `root`，密碼 `password`。

### 1.1 把 overlay 搬到 eMMC（第一次刷機必做）

原廠 rootfs 分割區只有幾十 MB，裝 deferred 套件前必須先把 overlay 搬到 eMMC 的大分割區。SSH 進去執行：

```sh
sh /root/expand-overlay-to-emmc.sh
```

跑完會要求重開機，重開後用 `df -h /overlay` 確認容量變成 100GB+ 等級（不是原本 ~30MB 的小分割區），才能繼續下一步。

## 2. 安裝 deferred 套件（PassWall2 / AdGuardHome / Tailscale / ModemManager / OpenVPN client / USB 4G5G）

這些套件為了讓 base image 塞得進 60MB 的 rootfs 分割區，被拆出來另外用 apk 補裝，**不是自動的**（避免開機時做網路相關的事）。確認 overlay 已經搬到 eMMC 後手動跑：

```sh
sh /root/install-deferred-packages.sh
```

這個腳本會從 GitHub Release 下載 `deferred-packages.tar.gz` 並用 `apk add` 裝好。裝完 LuCI 重新整理應該就能看到 PassWall2 / AdGuardHome / Tailscale 的頁面。

### 2.1 用自架 apk repo 裝套件（比手動下 tarball 更方便）

這個分支同時維護一個 `gh-pages` 分支當 apk repo（https://keyword1983.github.io/LibWrt/），裝好之後可以直接 `apk update` + `apk add <套件名>`，不用每次手動抓 tarball。加入方式：

```sh
cat >> /etc/apk/repositories.d/customfeeds.list << 'EOF'
https://keyword1983.github.io/LibWrt/aarch64_cortex-a53/base/packages.adb
https://keyword1983.github.io/LibWrt/aarch64_cortex-a53/luci/packages.adb
https://keyword1983.github.io/LibWrt/aarch64_cortex-a53/packages/packages.adb
EOF
apk update
```

以上三條是**跟核心版本無關**的一般套件（passwall2、adguardhome、mwan3 本體、各種 luci-app-* 等），任何時候都可以用。

**kmod（USB 4G/5G 驅動等）要另外加一條，而且要對版本**：kmod 內部記錄了它是對哪一版核心編的，裝錯版本的 kmod 會直接被 apk 擋掉（不會裝成半殘的錯誤版本，這點不用擔心裝壞）。每次重新刷機（核心版本可能因此改變）都會開一個新資料夾，資料夾名稱對應 firmware release 名稱，例如目前對應 `jdc-ax1800pro-20260805-1349` 這個 release 的：

```sh
echo "https://keyword1983.github.io/LibWrt/qualcommax/ipq60xx/jdc-ax1800pro-20260805-1349/packages.adb" \
  >> /etc/apk/repositories.d/customfeeds.list
apk update
```

刷到新版本後，先看資料夾裡的 `KERNEL.txt` 對一下 `apk list --installed | grep '^kernel-'` 的雜湊值是否一致，再換成對應新版本的資料夾網址（把上面這條換掉），不要把新舊版本的網址同時留著。

---

## 3. 各功能怎麼用

### 3.1 AdGuardHome（DNS 過濾/去廣告）

LuCI → Services → AdGuardHome。裝完後 dnsmasq 會自動把 DNS 轉給 AdGuardHome（監聽 `127.0.0.1#55`），有 `strictorder` fallback 到 `1.1.1.1`，AdGuardHome 掛掉也不會斷網。AdGuardHome 的資料目錄在 `/var/lib/adguardhome`（tmpfs，不會磨損 eMMC）。

### 3.2 PassWall2（代理）

LuCI → Services → PassWall2。第一次用要先在「節點列表」新增節點，然後在「基本設定」開啟。

### 3.3 Tailscale

LuCI → Services → Tailscale，或 SSH 用 `tailscale up` 登入你的 tailnet。

**要開 Exit Node / Subnet Router 才需要注意**：這個 build 已經把 `kmod-ipt-nat`、`kmod-ipt-conntrack`、`kmod-ipt-conntrack-extra`、`kmod-ipt-conntrack-label`、`kmod-nf-conncount` 都內建進 base image 了（tailscaled 管理 NAT/連線追蹤規則需要完整的舊式 xtables 模組,即使 firewall4 走 nftables）。如果從別的分支/版本刷過來、少了這些模組，開 exit node 時 tailscaled 插規則失敗可能會把全機連線搞壞（不只 tailscale 流量），碰到的話先 `tailscale down` 恢復。

手機/電腦連上 exit node 時要走哪個 DNS,是在 Tailscale 後台管理介面（不是路由器上）設定 MagicDNS 的 Global nameservers，跟路由器上是否開 exit node 是兩件事。

### 3.4 OpenVPN Client（換 IP 出網用）

LuCI → VPN → OpenVPN（跟 OpenVPN Server 同一層）。

1. 進去頁面右上角「新增」，貼上 instance 名稱
2. 或直接編輯設定：`option config` 指向你的 `.ovpn` 檔案路徑（例如 `/etc/openvpn/myclient.ovpn`），帳密用 `auth-user-pass` 指向另一個檔案
3. 存檔後在清單頁按 Start/Stop 開關

背後是傳統的 `/etc/init.d/openvpn` procd 多實例腳本（這個 build 沒有走 netifd 的 `proto=openvpn`，因為那條路在這個版本沒辦法穩定搶到預設路由，會導致「連上但換不了 IP」——細節見下方「已知限制」）。

**壓縮相容性**：這個 build 的 openvpn 已經啟用 LZO 支援（`CONFIG_OPENVPN_openssl_ENABLE_LZO=y`），連老式（pre-2.4、net30 拓樸）伺服器時如果連上但沒有資料流動、log 出現 `write to TUN/TAP: Invalid argument`，通常是伺服器端還在用舊式 comp-lzo framing——在 `.ovpn` 裡加一行 `compress lzo`（或視伺服器設定用 `compress migrate`）通常能解決。

**新增/修改 instance 後如果 LuCI 頁面沒反應或選單少東西**：這是 rpcd/uhttpd 快取的問題，SSH 執行：
```sh
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache*
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

### 3.5 USB 4G/5G 數據機（ModemManager）

支援 QMI、CDC-NCM、MBIM、RNDIS、AT 指令/序列埠模式，含多模式網卡自動切換（usb-modeswitch）。

1. 插上網卡，SSH 執行 `mmcli -L` 確認偵測到（沒偵測到通常是要等 usb-modeswitch 切完模式，等個幾秒再查）
2. LuCI → Network → Interfaces → Add new interface
3. Protocol 選「ModemManager」，選偵測到的裝置，填 APN
4. 存檔、Bring Up

**如果 Protocol 下拉選單裡沒有「ModemManager」選項**：netifd 只在自己啟動時掃描一次可用的協定處理器（`/lib/netifd/proto/*.sh`）。如果 modemmanager 套件是在 netifd 已經在跑的情況下才裝上去的（例如透過 deferred 套件補裝，而不是開機就內建），netifd 不會自動重新掃描。SSH 執行一次即可（會讓網路介面短暫重新載入,幾秒內恢復）：
```sh
/etc/init.d/network restart
```
之後瀏覽器重新整理，選單裡就會出現 ModemManager。這個限制只在「裝好套件後的第一次」需要處理，重開機後就正常了。

### 3.6 UPnP

LuCI → Services → UPnP，開啟即可，走 nftables（`miniupnpd-nftables`），跟這個 build 的 firewall4 一致。

### 3.7 mwan3（WAN + USB 4G/5G 備援，*目前尚未完整可用*）

seed.config 已經加了 `mwan3` + `luci-app-mwan3`，但它依賴的 `kmod-ip6tables`/`kmod-ipt-ipset` 目前這個 build 的核心裡還沒有（要重新編譯核心才會有，會跟現有已安裝的東西核心版本不一致，需要配合刷機一起做）。單純裝 `mwan3` 套件本身不會影響現有 WAN，但功能還沒法完整運作，等下一輪重編+刷機再處理。

---

## 4. 備份

用 LuCI「產生備份」或 `sysupgrade -b` 時，`/etc/config/*`（所有 UCI 設定）會自動包含。但以下這些不是 UCI 設定、預設不會被備份，已經加進 `/etc/sysupgrade.conf`：

- `/etc/openvpn/`（OpenVPN client 的 `.ovpn`/帳密檔、server 的 pki 憑證）
- `/etc/adguardhome/`（AdGuardHome 真正的設定內容，UCI 那邊只是個存根）
- `/etc/tailscale/`（Tailscale 登入狀態）
- `/etc/apk/repositories.d/`（自架 apk repo 設定，見 2.1）

如果是全新安裝、`/etc/sysupgrade.conf` 還是預設內容，先手動加上面幾行再做備份。

## 5. 已知限制

- **OpenVPN client 不要用 Network → Interfaces 的 `proto=openvpn` 方式設定**：實測過 netifd 那條整合路徑對「要接管預設路由換 IP」這種用法不穩定——tunnel 能連上、ubus 狀態也顯示路由已套用，但實際上那條 default route 常常沒有真正寫進 kernel routing table（這是 netifd 本身已知的一類 bug，跟版本/設定都無關）。要用 LuCI → VPN → OpenVPN 那個獨立頁面。
- **修改防火牆/openvpn/modemmanager 等設定後 LuCI 頁面異常**，優先懷疑快取（`/tmp/luci-indexcache`、`/tmp/luci-modulecache`）或 rpcd/netifd 沒有重新載入,不是設定本身壞掉。
- **關閉某個 netifd 網路介面要用 `option auto '0'`，不是 `option enabled '0'`**：後者對 netifd 沒有實際作用，`/etc/init.d/network restart`（不管是自己手動跑還是別的設定改動觸發的)都會把它重新帶起來。
