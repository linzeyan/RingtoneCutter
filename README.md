<p align="center">
  <img src="RingtoneCutter/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="鈴聲剪輯 icon">
</p>

<h1 align="center">鈴聲剪輯</h1>

<p align="center">把喜歡的歌剪成 iPhone 鈴聲</p>

<p align="center">正體中文 · <a href="README.en.md">English</a></p>

---

鈴聲剪輯把你手邊的音樂剪成 30 秒以內的鈴聲，不用電腦，也不用 GarageBand。

## 功能

- **三種來源**：
  - 「選擇檔案」：從「檔案」App 選音樂或影片，iCloud 雲碟、Google 雲端硬碟、Dropbox、OneDrive 都在裡面。
  - 「選擇影片」：從相簿挑影片，包括螢幕錄影。
  - 「貼上連結」：沒裝雲端硬碟 App 也能用，貼上 Google 雲端硬碟、Dropbox、OneDrive 的公開分享連結就會自動下載，S3 等直接下載的網址也可以。
- **看著波形剪**：上方是整首歌的縮圖，拖一下就換段落；下方放大 60 秒的波形，拖動把手或用 ±0.1 秒按鈕微調。片段不會超過鈴聲的 30 秒上限。
- **先試聽再製作**：播放位置即時顯示在波形上；淡入淡出預設開啟，試聽聽到的就是成品。
- **一鍵設成鈴聲**：按「製作鈴聲」、取名字，分享選單自動打開，點「用作鈴聲」就完成（iOS 26 以上）。
- **iCloud 同步**：右上角把儲存位置從 iPhone 切到 iCloud，剪好的鈴聲會存到 iCloud 雲碟的「鈴聲剪輯」資料夾，換手機或在 iPad、Mac 上都拿得到。iPhone 的鈴聲清單本身不跨裝置同步，另一台 iPhone 要從「檔案」打開那首再點「用作鈴聲」。
- **常見格式**：MP3、M4A、AAC、WAV、AIFF、FLAC、ALAC、Opus、AC-3，以及 MP4、MOV 影片的聲音。其他 App 裡的音檔也能直接用「鈴聲剪輯」打開。
- **不收集任何資料**：沒有廣告、帳號、App 內購買；只有貼上連結時才會連到那個網址下載。見[隱私權政策](PRIVACY.md)。

## 系統需求

- iPhone，iOS 18 以上。
- 「用作鈴聲」需要 iOS 26 以上。iOS 18–25 一樣能剪輯與製作，檔案存在「檔案」App →「我的 iPhone」→「鈴聲剪輯」，需要另外透過電腦同步成鈴聲。

## 問題回報

請到 [Issues](https://github.com/linzeyan/RingtoneCutter/issues) 留言。

## 開發

SwiftUI，沒有第三方相依套件。Xcode 專案由 `project.yml` 透過 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 產生，不進版控。

```bash
make setup         # 需要時安裝 XcodeGen，產生 RingtoneCutter.xcodeproj
make test          # 在 iPhone 模擬器跑單元測試
make run           # 建置並在模擬器啟動
make run-device    # 建置、安裝並在配對的 iPhone 啟動（DEVICE_ID）
make icon          # 把 design/AppIcon.svg 轉進 asset catalog（rsvg-convert）
make screenshots   # App Store 截圖，正體中文與英文（需要 ffmpeg）
make release       # Release archive 與 App Store IPA，輸出到 build/export/
```

| 路徑 | |
| --- | --- |
| `RingtoneCutter/` | App 原始碼、字串目錄（來源 `zh-Hant`，另有 `en`）、隱私清單 |
| `RingtoneCutterTests/` | 單元測試：片段長度上限、剪輯、淡入淡出、波形、分享連結轉換 |
| `RingtoneCutterUITests/` | 上架截圖流程，只由 `make screenshots` 執行 |
| `design/AppIcon.svg` | App 圖示原檔 |
| `scripts/` | 截圖用模擬器設定、附件重新命名 |
| `samples/demo.m4a` | 合成的 60 秒音檔，用來試「貼上連結」 |
