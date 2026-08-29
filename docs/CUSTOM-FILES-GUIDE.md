# OpenWrt 啟動與自訂腳本維護指南 (Custom Boot Scripts & Settings Guide)

本文件記載本專案中 `/files/etc/` 目錄下的自訂啟動腳本、UCI 預設設定（`uci-defaults`）、`rc.local` 配置，以及 **Block Wi-Fi（無線停用）** 的實現機制。

---

## 📁 檔案結構總覽

專案中所有預先打包進韌體檔案系統的自訂設定檔皆放置於 `files/` 目錄中：

```text
LibWrt/files/etc/
├── config/
│   └── fstab                     # NTFS3 掛載參數設定 (包含 force 與 iocharset=utf8)
├── modules.d/
│   └── 20-nls-utf8               # 最高優先級 UTF-8 語言模組載入檔
├── rc.local                      # 每次開機末段執行的系統優化指令
└── uci-defaults/
    ├── 97-wifi-driver-off.sh      # 首次開機停用 Wi-Fi 介面與驅動模組 (Block Wi-Fi)
    ├── 99-bbr.sh                 # 首次開機啟用 TCP BBR 擁塞控制
    └── 99-custom-settings.sh     # 首次開機系統、網路、MiniDLNA 與定時重開機預設優化
```

---

## ⚡ OpenWrt 啟動執行機制說明

OpenWrt 的系統啟動順序如下：

1. **`uci-defaults` (首次開機 / 刷機升級後第一次啟動)**：
   * **位置**：`/etc/uci-defaults/`
   * **執行腳本**：`/etc/init.d/boot` (START=10)
   * **特性與持久性**：僅在 **Firstboot** 時按檔名順序 (如 97 -> 99) 執行 **一次**。執行成功 (Exit Code 0) 後，系統會自動 `rm -f` 刪除該腳本。
   * **重開機是否會失效？不會**。因為腳本內執行的 `uci commit wireless` 與 `mv /etc/modules.d/...` 都是將修改**永久寫入 Overlay (可讀寫檔案系統)**，因此即使腳本被刪除，每次重開機**仍會持續維持停用 Wi-Fi 狀態**。

2. **`init.d` 服務 (每次開機)**：
   * **位置**：`/etc/init.d/`
   * **執行順序**：按 `START=xx` 順序執行（如 `START=95` 的 `/etc/init.d/done`）。

3. **`rc.local` (每次開機最後一刻)**：
   * **位置**：`/etc/rc.local`
   * **執行腳本**：由 `/etc/init.d/done` (START=95) 呼叫 `sh /etc/rc.local` 執行。
   * **特性**：每次開機最後執行，適合放置常態性的 Shell 命令。

---

## 🛡️ Block Wi-Fi 設定細節 (`97-wifi-driver-off.sh`)

* **檔案路徑**：`files/etc/uci-defaults/97-wifi-driver-off.sh`
* **目的**：針對**亞瑟 (Arthur, JDC AX1800 Pro)** 作為純有線主路由器使用時，於首次開機時自動全面停用 Wi-Fi 介面與載入驅動以省下記憶體；對於**雅典娜 (Athena, JDC AX6600)** 或其他機型，則自動跳過本腳本，**維持無線 Wi-Fi 正常開啟與連線**。

### 實現動作
1. **UCI 關閉無線介面**：
   * 搜尋 `/etc/config/wireless` 中的所有 `wifi-device` 與 `wifi-iface`。
   * 強制設定 `disabled='1'` 並執行 `uci commit wireless`。
2. **阻斷驅動模組載入**：
   * 搜尋 `/etc/modules.d/` 下的無線相關驅動配置文件（`*ath11k*`、`*-mac80211`、`*-cfg80211`）。
   * 將檔案重命名加上 `.disabled` 後綴，避免 Linux Kernel 在開機時自動載入無線網卡驅動。

### 如何手動恢復 Wi-Fi 功能？
若未來有啟用 Wi-Fi 的需求，需手動復原：
```sh
# 1. 恢復驅動模組載入檔案
for f in /etc/modules.d/*.disabled; do
    [ -e "$f" ] && mv "$f" "${f%.disabled}"
done

# 2. 重新啟用 UCI 無線設定
uci set wireless.radio0.disabled='0'
uci set wireless.default_radio0.disabled='0'
uci commit wireless

# 3. 重開機或重新載入驅動
reboot
```

---

## ⚙️ 首次開機優化腳本說明

### 1. `files/etc/uci-defaults/99-custom-settings.sh`
包含系統、網路、硬體頻率與套件的綜合設定：
* **網路優化**：啟用 IGMP Snooping、配置 mwan3 WAN 權重 (WAN=1, USB_WAN=2, MM_WAN=3)、加入 USB/MM WAN 至 Firewall WAN Zone。
* **CPU 調頻與硬體適配**：
  * 通用調頻：`schedutil` 864MHz - 1512MHz。
  * 依機型微調：Arthur (JDC AX1800 Pro) 上限 1.200GHz (`minfreq0=864000`, `maxfreq0=1200000`)；Athena (JDC AX6600) 上限 1.800GHz。
  * **LuCI 介面設定**：本專案已整合 **`luci-app-cpufreq`** 套件，刷機後可在 LuCI 選單 **「系統」 -> 「CPU 調頻 (CPU Freq)」** 中直接以圖形介面調整策略 (Governor) 與高低頻範圍。
* **服務初選**：配置 Dropbear SSH Interface、MiniDLNA (Port 8200)、AdGuard Home (預載 anti-AD + OISD Small 選項)。

### 2. `files/etc/uci-defaults/99-bbr.sh`
* **內容**：將 `net.core.default_qdisc=fq` 與 `net.ipv4.tcp_congestion_control=bbr` 自動追加至 `/etc/sysctl.conf`，提升高延遲/跨國鏈路的網路吞吐量。

---

## 🚀 每次開機執行腳本 (`rc.local`)

* **檔案路徑**：`files/etc/rc.local`
* **內容與用途**：
  ```sh
  echo schedutil > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null
  echo 2048 > /sys/block/mmcblk0/queue/read_ahead_kb 2>/dev/null
  echo 2048 > /sys/block/sda/queue/read_ahead_kb 2>/dev/null

  exit 0
  ```
* **說明**：
  1. 確保 CPU scaling governor 在開機完成後維持在 `schedutil` 模式。
  2. 將 eMMC 儲存裝置 (`mmcblk0`) 與外接 USB/SATA 磁碟 (`sda`) 的 Read-ahead 快取調大至 2048 KB，以提升磁碟 I/O 隨機讀取效能。

---

## 🛠️ 開發與維護注意事項

1. **檔案權限**：`files/etc/uci-defaults/` 與 `files/etc/rc.local` 下的 Shell 腳本請確保具備可執行權限 (`chmod +x`)。
2. **語法與邏輯**：`uci-defaults` 腳本必須確保語法正確且傳回 `0`。若腳本執行失敗，OpenWrt 就不會刪除該腳本，導致下次開機時重複執行。
3. **路徑引用**：修改設定時，請優先使用 `uci set` 與 `uci commit` 指令，維護標準 OpenWrt 配置格式。
