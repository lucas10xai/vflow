# vflow — client macOS

Giữ **⌥ Option trái**, nói, nhả phím ⇒ chữ được dán vào ô đang gõ ở mọi ứng dụng (kể cả Terminal). **Đúp ⌥ trái** (hai lần chạm nhanh) ⇒ ghi "khoá" (hands-free, không cần giữ phím) — bấm ⌥ một lần nữa để xong. **Esc** huỷ ngay lập tức ở bất kỳ kiểu ghi nào. Giữ **⌥ trái + ⌃ trái** (⌃ trong 400 ms đầu) ⇒ Command Mode (sửa/soạn văn bản bằng lời, xem mục riêng bên dưới). Client chỉ nói chuyện với engine cục bộ `http://127.0.0.1:7611` theo `contract/engine-api.md`; không mạng ngoài, không analytics, không tự cập nhật, không thư viện bên thứ ba.

Từ M4a, vflow là **app thường**: biểu tượng Dock, ⌘-Tab, menu ứng dụng đầy đủ, và cửa sổ chính **"vflow"** với 5 mục xếp theo 2 nhóm ở thanh bên — **Sử dụng** (Tổng quan, **Thống kê** [V2], Lịch sử), **Cá nhân hoá** (Từ điển, Snippets); **Cài đặt** (từ U1, mở rộng ở V2 với các mục Giọng nói/Ứng dụng/Dữ liệu) là **cửa sổ RIÊNG chuẩn macOS** (⌘,; menu "vflow › Cài đặt…"), không còn là một mục trong thanh bên. Biểu tượng thanh menu vẫn còn nhưng chỉ là phụ (có công tắc ẩn/hiện ở Cài đặt › Chung, mặc định bật) — từ U1, biểu tượng này là ảnh **TEMPLATE đơn sắc** (`isTemplate = true`): macOS tự vẽ **trắng** trên thanh menu tối, **đen** trên thanh menu sáng; trạng thái (nghe/dịch/lỗi/thiếu quyền) phân biệt bằng **hình** huy hiệu góc dưới-phải (chấm đặc/vòng/sao lấp lánh/tam giác cảnh báo — xem mục Logo), không dựa vào màu. **Đóng cửa sổ chính (nút đỏ) KHÔNG thoát app** — ghi âm bằng phím nóng và engine vẫn hoạt động; thoát hẳn bằng **⌘Q** hoặc menu "vflow › Thoát vflow". Lần đầu mở (hoặc khi chưa đủ 3 quyền macOS), một tờ **Chào mừng** tự hiện hướng dẫn cấp quyền từng bước (dấu tích tự cập nhật); mở lại được bất cứ lúc nào từ menu "Trợ giúp › Xem hướng dẫn chào mừng…".

Từ M4b, bản dựng mặc định (`build-app.sh`, không có `--no-bundle`) **tự đủ**: Node 22, mã engine, `node_modules` (chỉ darwin-arm64) và model `zipformer-vi-30m` nằm sẵn trong `VFlow.app/Contents/Resources/` — không cần repo hay Node cài trên máy chạy. Xem mục "Đóng gói tự đủ & cài đặt" bên dưới.

## Dựng và chạy
```sh
client/scripts/make-icon.sh            # (chỉ cần khi đổi logo) ⇒ AppIcon.icns + menubar-mark-18{,@2x,@3x}.png từ Resources/branding/
client/scripts/make-signing-identity.sh --yes   # (một lần, CẦN chủ dự án duyệt) ⇒ danh tính ký ổn định "vflow Local Signing"
client/scripts/build-app.sh            # ⇒ client/build/VFlow.app (release, TỰ ĐỦ: kèm Node+engine+model; ký bằng danh tính ổn định nếu có, không thì ad-hoc; codesign --verify)
client/scripts/build-app.sh --no-bundle  # như trên nhưng KHÔNG đóng gói engine (dựng nhanh khi phát triển; cần repo + Node hệ thống như trước M4b)
client/scripts/build-app.sh --clean    # xoá client/.build (~ vài trăm MB) sau khi dựng; kết hợp được với --no-bundle
open client/build/VFlow.app
cd client && swift test                # test logic thuần (VFlowCore)
```
Yêu cầu: macOS 14+, Xcode/Swift 6. Cờ dòng lệnh của nhị phân `VFlow.app/Contents/MacOS/VFlow`:
- `--demo-overlay ghi|khoa|dich|xong|loi [--demo-seconds N]`: chỉ hiện thanh trạng thái ở một trong 5 trạng thái (để chụp ảnh), không chạy engine/phím nóng.
- `--no-prompt`: không bật hộp thoại xin quyền (dùng khi chạy thử tự động); vẫn kiểm và báo trạng thái quyền.
- `--open-tab tongquan|thongke|lichsu|tudien|snippet|caidat`: mở cửa sổ chính thẳng vào mục đó (`thongke` = tab Thống kê, V2); riêng `caidat` mở CỬA SỔ CÀI ĐẶT (không còn là mục trong thanh bên) — dùng để chụp ảnh.
- `--open-settings-tab general|voice|apps|cloud|data|hotkeys|historyPrivacy|advanced`: mở cửa sổ Cài đặt thẳng vào mục đó (chụp ảnh). `voice`/`apps`/`data` là 3 mục mới ở V2 (xem mục "V2" bên dưới).
- `--appearance light|dark`: ép giao diện sáng/tối (chỉ để chụp ảnh nhất quán, không đổi cài đặt hệ thống).
- `--no-welcome`: không tự hiện tờ Chào mừng lần đầu dù chưa đủ quyền/chưa từng xem (dùng khi chụp ảnh các cửa sổ khác để tờ Chào mừng không che mất).
- `--demo-icon [--demo-seconds N]`: cửa sổ RIÊNG hiện biểu tượng thanh menu (template) trên nền tối/sáng ở cả 5 trạng thái huy hiệu, không chạy engine/phím nóng — dùng để chụp ảnh chứng minh trắng/đen tự động mà không chụp thanh menu thật.
- `--render-offscreen <mục> --out <path.png> [--render-wait-ms N]`: chụp một mục ra PNG mà KHÔNG BAO GIỜ hiện cửa sổ lên màn hình — xem mục "Công cụ chụp ảnh ngoài màn hình" bên dưới (U3).

Biến môi trường `VFLOW_HOME` (mặc định `~/.vflow`, giống engine) đổi nơi client đọc `client.json`/`token` và lưu `history.jsonl` — dùng để thử nghiệm mà không đụng dữ liệu thật, ví dụ: `VFLOW_HOME=/tmp/vflow-test VFlow.app/Contents/MacOS/VFlow`. **Từ U2**: khi có `VFLOW_HOME`, các công tắc UI (chế độ, Lưu lịch sử, Hiện cửa sổ khi mở app, Hiện biểu tượng thanh menu, đã xem Chào mừng…, vị trí/kích thước cửa sổ) cũng được CÔ LẬP — dùng một `UserDefaults(suiteName:)` suy ra từ `VFLOW_HOME` bằng băm ổn định FNV-1a (`VFlowCore.VFlowDefaults`, một lớp truy cập duy nhất thay mọi chỗ gọi `UserDefaults.standard`/`setFrameAutosaveName` trực tiếp — xem `VFlow.WindowFramePersistence`), nên hai `VFLOW_HOME` khác nhau và bản `/Applications/vflow.app` thật KHÔNG còn thấy khoá của nhau. KHÔNG có `VFLOW_HOME` ⇒ `.standard` như cũ (không di cư dữ liệu, app thật không đổi hành vi).

Hai biến môi trường CHỈ dùng để chụp ảnh tự động (không có tác dụng gì khi không đặt, không bao giờ dùng khi chạy thật):
- `VFLOW_DEMO_PERMISSIONS=granted|missing`: giả lập quyền macOS đủ/thiếu mà không đụng TCC thật.
- `VFLOW_DEMO_MENUBAR_OCCLUDED=1` (U4): ép thẻ nhắc "biểu tượng thanh menu bị che" ở Tổng quan luôn hiện, không phụ thuộc toạ độ màn hình thật lúc chụp (không đoán trước được máy kiểm có notch/thanh menu đủ chật hay không).

(U3 dọn: `VFLOW_PRINT_WINDOW_RECT`/`WindowRectDebug.swift` — cơ chế cũ in toạ độ để chụp bằng
`screencapture -R`/`-l` — đã bị thay hẳn bởi `--render-offscreen`/`snapshot.sh` bên dưới, không còn
script nào đặt biến này nên đã xoá.)

## Công cụ chụp ảnh ngoài màn hình (`--render-offscreen`, U3)

**Nguyên tắc cứng, không bao giờ phá vỡ:** công cụ này KHÔNG BAO GIỜ được gọi `makeKeyAndOrderFront`/
`orderFront`/`NSApp.activate()` trên bất kỳ cửa sổ nào — kể cả tạm thời. Sự cố đã từng xảy ra (U2):
một worker lỡ chụp toàn màn hình lúc chủ dự án đang họp/trình chiếu. Từ đó: **mọi** ảnh chụp để kiểm
tra/so sánh bố cục phải render cây view THẬT (không viết view giả) vào một `NSWindow` **không bao giờ
hiện**, dùng `NSView.cacheDisplay(in:to:)` (không phải `screencapture`, không phải chụp màn hình thật
dưới bất kỳ hình thức nào). Mọi script/đoạn mã mới thêm vào phải grep sạch — không có `screencapture`
hay "set frontmost"/`activate()` nào.

### Cách hoạt động
`VFlow.app/Contents/MacOS/VFlow --render-offscreen <mục> --out <path.png> [--appearance light|dark] [--render-wait-ms N] [--no-prompt] [--no-welcome]`:
1. Đặt `NSApp.setActivationPolicy(.prohibited)` + tắt hộp xin quyền hệ thống (`PermissionKind.promptsEnabled = false`) — tiến trình không có Dock icon, không bật hộp thoại nào.
2. Dựng app THẬT qua `AppController.start(initialTab:)` (engine/dữ liệu thật qua `VFLOW_HOME`) — KHÔNG qua view/preview giả.
3. Gọi `StatusWindowController`/`SettingsWindowController`/`WelcomeWindowController`.`captureOffscreen(...)` → `OffscreenRender.captureRealWindow`: đặt `window.alphaValue = 0` + toạ độ rất xa mọi màn hình thật (`x = -50000`), gọi `layoutSubtreeIfNeeded()` rồi `view.bitmapImageRepForCachingDisplay` + `cacheDisplay(in:to:)` — **không bao giờ** `orderFront`/`orderBack` (đã đo: `orderBack` có thể khiến AppKit tự dịch cửa sổ vào lại vùng màn hình thật khi lần đầu gắn vào screen — KHÔNG DÙNG).
4. In `VFLOW_OFFSCREEN_CHECK` (đếm cửa sổ on-screen thật qua `CGWindowListCopyWindowInfo` — PHẢI luôn là 0) trước khi thoát.

`<mục>`: `tongquan`, `thongke` (V2), `lichsu`, `tudien`, `tudien:them-loi` (sheet Thêm mục với lỗi hợp lệ sẵn — GIỚI
HẠN: ảnh chỉ có cửa sổ chính, sheet không hiện trong ảnh — xem ghi chú ở
`StatusWindowController.captureDictionaryAddInvalidOffscreen`), `snippet`,
`caidat[:general|voice|apps|cloud|data|hotkeys|historyPrivacy|advanced]`, `welcome`. HUD (thanh trạng thái 5 trạng thái) dùng
`--demo-overlay <ghi|khoa|dich|xong|loi> --render-offscreen --out <path>` (không cần `<mục>`).

### `client/scripts/snapshot.sh <thư mục đầu ra>`
Công cụ LÂU DÀI chụp TOÀN BỘ màn hình (sáng + tối): dựng VFlow, tạo BA `VFLOW_HOME` cô lập tạm thời,
MỖI cái chạy một engine THẬT riêng (cổng riêng 27611/27612/27613, chỉ 127.0.0.1) —
(`full`: dữ liệu mẫu đầy đủ, gồm ~16 tuần thống kê đa dạng + vài ứng dụng (Safari/Slack thật, "Zalo"
minh hoạ, "unknown") + gợi ý từ điển sẵn; `empty`: trống hoàn toàn (0 từ, không dictionary/snippets),
quyền giả lập thiếu; `statsoff`: GIỐNG `full` nhưng `config.json` đặt sẵn `stats_enabled:false`) —
gọi `--render-offscreen` cho từng cặp (mục, sáng/tối), rồi dọn sạch TẤT CẢ (3 tiến trình engine, 3
thư mục tạm) — không đụng `~/.vflow` thật, không để lại tiến trình/thư mục tạm. Dữ liệu mẫu trong
`snapshot-seed.mjs` không chứa tên riêng/khoá thật ("Zalo" chỉ là bundle id minh hoạ hợp lệ, CHƯA
xác minh đúng bundle id thật của app đó — không quan trọng cho ảnh chụp vì máy dựng không cài app
này, client tự rơi về biểu tượng chung, đúng hành vi thật khi gặp app lạ).

```sh
client/scripts/snapshot.sh /tmp/vflow-snapshots   # ⇒ 46 ảnh PNG, xem /tmp/vflow-snapshots/snapshot.log
```

### Giới hạn đã biết (nói thẳng, không che giấu)
- **Hàng trong `List`** (Lịch sử/Từ điển/Snippets) không luôn vẽ ra trong ảnh dù dữ liệu tải đúng
  (tiêu đề "Lịch sử (N)"/"Từ điển (N)" hiện đúng số) — đã điều tra kỹ (xem ghi chú tại
  `StatusWindowController.captureOffscreen`): không phải lỗi thời gian (đã thử đợi tới 5 giây), không
  phải do chuyển mục (đã thử dựng thẳng vào mục đó), các trường hợp `List` đơn giản/có `Section`/lồng
  trong `ScrollView` đều chụp đúng khi thử tách riêng — chỉ sai trong cây cửa sổ ĐẦY ĐỦ. Chưa tìm ra
  biến cụ thể trong thời gian cho phép. KHÔNG liên quan tới lỗi bố cục U3 đã sửa (thanh bên/Tổng quan
  đã đúng, có test hồi quy).
- **`.sheet`** (ví dụ Thêm mục từ điển) là một `NSWindow` CON riêng (`NSWindow.attachedSheet`) —
  `beginSheet` chỉ gắn được khi cửa sổ cha `isVisible`; đã thử `orderBack` để bật `isVisible` mà
  không đưa cửa sổ lên trước, nhưng đo được AppKit có thể tự dịch cửa sổ cha vào lại vùng màn hình
  thật — KHÔNG AN TOÀN nên đã bỏ. Ảnh `tudien:them-loi` vì vậy chỉ có cửa sổ chính, không có sheet.
- Thanh bên dùng vật liệu hệ thống (`NavigationSplitView` sidebar) — đã kiểm bằng ảnh chụp thật qua
  `--render-offscreen` (không qua `swift test` CLI thuần) ra đúng màu/vật liệu sáng-tối; nếu tự dựng
  cửa sổ thử trong một tiến trình CLI khác (không qua đường `AppController.start()` đầy đủ) có thể
  không thấy đúng vật liệu — luôn dùng đường `--render-offscreen`/`snapshot.sh` thật, không tự chế.

## Đóng gói tự đủ & cài đặt (M4b)

```sh
client/scripts/bundle-engine.sh client/build/VFlow.app   # gọi tự động từ build-app.sh, hiếm khi cần chạy tay
client/scripts/install-app.sh      # dựng bản đầy đủ rồi cài vào /Applications/vflow.app
client/scripts/uninstall-app.sh    # gỡ /Applications/vflow.app (KHÔNG đụng ~/.vflow)
```

**`bundle-engine.sh`** đóng gói vào `VFlow.app/Contents/Resources/`:
- `engine/node/bin/node`: Node 22 LTS chính thức (darwin-arm64) tải từ nodejs.org, kiểm sha256 với `SHASUMS256.txt` chính thức, cache ở `client/.cache/` (không commit).
- `engine/{bin,engine,eval,config,package.json,node_modules}`: mã engine (bỏ `*.test.js`), `node_modules` chỉ dependency chạy thật của **đúng kiến trúc máy chạy `npm ci`** (darwin-arm64; không lẫn `sherpa-onnx-win-*`/`linux-*` vì đó là optionalDependencies theo nền tảng của npm).
- `models/zipformer-vi-30m/`: lấy từ `~/.vflow/models/zipformer-vi-30m` (đã kiểm checksum theo manifest ở cả nguồn lẫn sau khi chép vào bundle); KHÔNG đóng gói model streaming/PhoWhisper.
- `LICENSES/`: Node, sherpa-onnx (Apache-2.0), onnxruntime (MIT), mô tả giấy phép model (CC-BY-NC-ND-4.0 — **chỉ dùng cá nhân, phi thương mại**).
- Ký ad-hoc từng nhị phân lồng nhau (`node`, `*.node`, `*.dylib`) rồi ký cả bundle; `build-app.sh` kiểm `codesign --verify --deep --strict`.

**Thứ tự ưu tiên cấu hình engine** (xem `ClientConfig.resolve`, `EnginePortResolution`): `~/.vflow/client.json` (người dùng tự đặt `repo`/`node`) > engine đóng gói trong bundle (`Contents/Resources/engine`, mặc định khi có) > suy ra repo dev từ đường dẫn `<repo>/client/build/VFlow.app` (khi dựng `--no-bundle`). Không bao giờ âm thầm rơi về cổng mặc định khi cấu hình lỗi/chưa biết.

**Model lần đầu**: nếu bundle có kèm model và `~/.vflow/models/zipformer-vi-30m` CHƯA có, app tự chép sang (nguyên tử qua thư mục tạm + đổi tên, kiểm sha256 từng tệp theo manifest sau khi chép, dọn thư mục tạm nếu lần trước bị gián đoạn) — xem `VFlowCore.ModelBootstrap`. Model đã có ở `~/.vflow` thì **không bao giờ bị đè**. Trạng thái/lỗi hiện ở tab Tổng quan.

**`install-app.sh`** (sửa ở U1, rồi sửa tiếp ở U2 — xem bên dưới): dựng bản đầy đủ, thoát nhẹ nhàng (AppleScript `tell application id "org.aios.vflow" to quit`, chờ tối đa 15s, không `kill -9`) khi có tiến trình vflow có đường dẫn thực thi trong `client/build/VFlow.app` hoặc `/Applications/vflow.app` (dò case-insensitive vì `ditto` đổi tên thư mục đích thành chữ thường "vflow.app" khác với "VFlow.app" trong `client/build`). **U2**: trước đây gửi quit qua `tell application "System Events" ... quit (first process whose unix id is N)` — đã đo thật KHÔNG làm vflow thoát (script chờ hết 15s rồi từ chối cài đè đúng thiết kế, nhưng vô dụng vì tiến trình chưa hề thoát); gửi theo BUNDLE ID (cố định `org.aios.vflow` cho cả bản dựng và bản đã cài, xem `CFBundleIdentifier` ở `build-app.sh`) mới thoát được (~1s). **SAU ĐÓ KIỂM LẠI bằng `pgrep`** cả tiến trình vflow lẫn engine con (`vflow.js serve`) của nó đã thoát hẳn chưa — còn sống thì **DỪNG (mã khác 0), không chép đè**, chỉ in cảnh báo rồi tiếp tục như trước là lỗi đã sửa (U1). Sao chép bằng `ditto` sang `/Applications/vflow.app` (có bản cũ thì sao lưu ra `~/.vflow/backup/vflow.app.bak.<giờ>` trước, in dung lượng, rồi XOÁ các bản sao lưu cũ hơn do chính script tạo — chỉ giữ MỘT bản gần nhất), gỡ cách ly (`xattr -dr com.apple.quarantine`), kiểm chữ ký. Không dùng `sudo`; thiếu quyền ghi `/Applications` thì dừng. Có bản đang chạy trước khi cài (vừa thoát ở bước trên) ⇒ sau khi cài xong tự `open` lại bản mới, in PID + thời điểm bắt đầu. Biến môi trường `VFLOW_INSTALL_SRC_APP`/`VFLOW_INSTALL_DEST_APP`/`VFLOW_INSTALL_BACKUP_DIR`/`VFLOW_INSTALL_SKIP_BUILD`/`VFLOW_INSTALL_NO_REOPEN`/`VFLOW_INSTALL_QUIT_TIMEOUT_SECONDS` chỉ dùng cho `scripts/install-app.test.js` (shim, biên dịch hai tiến trình giả thật bằng `cc` để khớp cách `install-app.sh` nhận diện tiến trình qua `ps -o comm=`), không dùng khi cài thật.

**Lưu ý chữ ký**: bản ad-hoc trong `/Applications/vflow.app` được ký lại độc lập với bản trong `client/build/` mỗi lần cài — macOS sẽ coi là "app khác" và đòi cấp lại quyền macOS (Micro, Theo dõi đầu vào, Trợ năng) cho bản `/Applications`, đó là bản dùng thật.

### Nợ kỹ thuật
`bin/vflow.js` có import TĨNH ở đầu file từ `eval/metrics.js`, `eval/bench.js`, `eval/evaluate.js` (dùng cho lệnh `record`/`bench`/`compare`, không phải `serve`). Vì vậy `bundle-engine.sh` phải đóng gói cả các tệp `.js` ở gốc `eval/` (bỏ `*.test.js`, `eval/reports`, `eval/prompts`, `eval/phowhisper-server`) chứ không chỉ `bin/`+`engine/` như dự kiến ban đầu — nếu không `node bin/vflow.js serve` sẽ lỗi `ERR_MODULE_NOT_FOUND` ngay khi khởi động dù lệnh `serve` không cần các module đó. Nên đổi các import này sang `import()` động trong `bin/vflow.js` (việc của engine/, ngoài phạm vi `client/` — coordinator giao ở task khác).

## Cấu trúc
| Target | Nội dung |
|---|---|
| `VFlowCore` (thư viện, test được) | `Hotkey.swift` máy trạng thái phím (giữ/đúp-khoá/Command Mode/Esc) + phân loại CGEvent; `Audio.swift` bộ chuyển 16 kHz mono Int16 theo khối (sinc cửa sổ Blackman, chống răng cưa), downmix, LE, mức âm, bộ đệm “thử lại”; `Clipboard.swift` chèn bằng clipboard + khôi phục; `SelectionCapture.swift` lấy đoạn đang chọn (AX/⌘C tổng hợp, có kiểm soát) cho Command Mode; `TextMatch.swift` (`VietnameseMatch`) gấp dấu/chuẩn hoá khớp luật engine (`fold`/`normalizeMatch`); `EngineAPI.swift` yêu cầu/phản hồi/ánh xạ lỗi tiếng Việt (transcribe, healthz, dictionary, corrections, snippets, settings, command); `EngineSupervisor.swift` giám sát engine con; `ClientConfig.swift`; `VFlowHome.swift` tôn trọng `VFLOW_HOME`; `History.swift` (`HistoryStore`, `HistoryEntry`, `HistoryGate`) lưu lịch sử chỉ-văn-bản vào `history.jsonl`; `Dictionary.swift`/`DictionaryOrchestration.swift` và `Snippet.swift`/(`SnippetOrchestration` trong cùng tệp) kiểm hợp lệ + mẫu đọc-sửa-ghi chung cho `/v1/dictionary` và `/v1/snippets`; `Settings.swift` (`AppSettings`, `SettingsPatch`, `SettingsValidation`, `EnterAction`) cho `/v1/settings` và quyết định gửi phím Enter; `Dictation.swift`, `Overlay.swift` (gồm trạng thái ghi khoá/Command Mode) quyết định hiển thị; `StatusModel.swift` mô hình thuần dùng CHUNG cho menu và tab Tổng quan (`StatusModel`, `PermissionKind`/`PermissionItem`, `ConflictDetector`/`ConflictText` dò ứng dụng đọc chính tả khác qua `RunningAppsProvider`, `ShowWindowPreference`); `DesignSystem.swift` (U1, hệ thống thiết kế thuần) — `BrandColor`/`ContrastText` (màu nhấn cam #ED6300 + kiểm tương phản WCAG AA), `ModeCloudLabel` (nhãn "Trong máy"/"Gửi chữ qua 9Router" lấy từ `DictationMode.sendsTextToCloud`), `ModelReasonText` (mã lý do model → chữ thân thiện), `PermissionsProgress` ("n/3"), `WelcomeDecision` (có tự hiện Chào mừng hay không), `HeroStatus`/`HeroStatusDecision` (trạng thái thẻ lớn Tổng quan), `TodaySummary`/`TodayStats` (tổng hợp "Hôm nay" từ lịch sử); `VFlowDefaults.swift` (U2, lớp truy cập UserDefaults duy nhất, cô lập theo `VFLOW_HOME`); `HistoryGrouping.swift` (U2, gom lịch sử theo ngày); `ListSorting.swift` (U2, sắp xếp A–Z/dùng nhiều dùng chung Từ điển/Snippets); `DictionaryFormValidation`/`SnippetFormValidation` (U2, trong `Dictionary.swift`/`Snippet.swift`, kiểm hợp lệ ngay khi gõ); `WaveformMeter` (U2, trong `Overlay.swift`, chiều cao vạch sóng âm theo mức); `HoldModifierKey`/`HotkeyKeyConfig`/`ActiveHotkeyConfig`/`HotkeyConfigValidation`/`HotkeyChord`/`ReinsertChordPreset` (U4, trong `Hotkey.swift`, cấu hình phím "giữ để nói"/Command Mode/"Chèn lại câu vừa rồi" tuỳ chỉnh — `KeyClassifier.classify(config:)` tổng quát hoá, giữ mặc định y hệt bản cứng cũ); `LastSpokenText` (U4, trong `History.swift`, nguồn "câu vừa rồi"); `MenuBarOcclusion.swift` (U4, dò biểu tượng thanh menu bị che bằng toạ độ thuần + `MenuBarOcclusionReminder` nhắc theo ngày); `VoiceActivity.swift` (U4: `VoiceActivityDetector` VAD năng lượng thích nghi, `MicrophoneSelection` chọn/rơi về micro mặc định, `RecordingLimit` giới hạn ghi hands-free). |
| `VFlow` (AppKit/SwiftUI mỏng) | event tap, AVAudioEngine, NSPasteboard + ⌘V/Return/⌘C tổng hợp (`TextInserter.swift`: `PasteKeystroke`/`ReturnKeystroke`/`CopyKeystroke`/`AXSelection`/`PasteTargetActivator` — luôn dán, không dò ô nhập), NSPanel thanh trạng thái, `main.swift` (menu ứng dụng, `--open-tab`, `--open-settings-tab`, `--appearance`, `--no-welcome`, `--demo-icon`, `applicationDockMenu` U4), `StatusWindow.swift` cửa sổ chính "vflow" (`MainWindowView`, sidebar 5 mục xếp 2 nhóm + ⌘1…⌘5 + nút Cài đặt cố định U4; `StatsView.swift` V2 tab Thống kê), `SettingsWindow.swift` cửa sổ Cài đặt RIÊNG (`SettingsRootView`, 5 mục `SettingsCategory` = `VFlowCore.SettingsPane` từ Q1: Chung/Giọng nói/Ứng dụng/Dữ liệu & Riêng tư/Nâng cao; ⌘,), `WelcomeWindow.swift` tờ Chào mừng lần đầu (`WelcomeView`, cờ `hasSeenWelcome`), `Theme.swift` màu nhấn thương hiệu + `cardBackground()` dùng chung, `OverviewView.swift` (bảng điều khiển, U1, + `MenuBarOcclusionCard` U4) /`HistoryView.swift`/`DictionaryView.swift`/`SnippetsView.swift`/`SettingsView.swift` (gồm `ModeSection`, `GeneralSettingsTab` + `MicrophonePickerSection`/`SilenceStopSection` U4, `AdvancedSettingsTab` gộp 9Router + độ trễ + thông tin kỹ thuật) và `SettingsViewV2.swift` (`VoiceSettingsTab` gộp phím tắt, `AppsSettingsTab`, `DataSettingsTab` gộp lịch sử & riêng tư) nội dung từng mục, `MainTab.swift`, NSStatusItem + menu (`StatusMenu.swift`, có `setVisible`, `itemWindowFrame`/`setStableAutosaveName` U4, `populate(_:model:controller:)` dùng CHUNG với menu Dock, dùng `BrandIcon` cho biểu tượng template + huy hiệu trạng thái), `BrandIcon.swift` nạp logo-mark màu (header) và logo-mark template (thanh menu) từ bundle, `Permissions.swift` (quyền thật, nối `PermissionKind`, có cờ môi trường `VFLOW_DEMO_PERMISSIONS` chỉ-để-chụp-ảnh), `ConflictProvider.swift` (`NSWorkspace` thật), SMAppService, `WindowFramePersistence.swift` (U2, tự lưu/đọc vị trí cửa sổ qua `VFlowDefaults` khi có `VFLOW_HOME`, dùng `setFrameAutosaveName` chuẩn AppKit khi không có), `AudioRecorder.swift` (U4: `availableDevices()`/ghim thiết bị qua CoreAudio, `onLevel` nuôi VAD), `HotkeyMonitor.swift` (U4: `ActiveHotkeyConfig`/`keyConfig` đổi được, `onReinsertChord`). |
| `VFlowCoreTests` | swift-testing, chỉ logic thuần, dùng bộ chạy tiến trình/clipboard/đồng hồ giả. |

## Engine
- Khởi động: hỏi `GET /healthz` ở `127.0.0.1:<port>`. Có engine vflow hợp lệ ⇒ **dùng lại**, không chạy thêm (và khi thoát **không** tắt engine đó). Có tiến trình khác chiếm cổng ⇒ báo lỗi. Không có ⇒ chạy `node <repo>/bin/vflow.js serve --port <port>` làm tiến trình con (biến `VFLOW_PORT`, `PATH` tối thiểu gồm thư mục của node).
- Engine con chết ⇒ khởi động lại, lùi dần 0,5 s → 1 → 2 → 4 → 8 s (trần 16 s); quá **5 lần trong 60 s** ⇒ dừng và báo “Engine chết liên tục…” kèm mã thoát và dòng log stderr cuối (chỉ giữ trong RAM); menu có “Khởi động lại engine”. Engine có sẵn biến mất ⇒ tự chạy engine con.
- Thoát app (menu, ⌘Q, `quit`, SIGTERM/SIGINT) ⇒ SIGTERM engine con, chờ 2 s, rồi SIGKILL. Nếu app bị SIGKILL/crash thì engine con mồ côi vẫn chạy; lần mở sau app sẽ dùng lại nó qua `/healthz`.
- Token đọc từ `~/.vflow/token` ở **mỗi** lần gửi (engine tự tạo khi chạy lần đầu). Thiếu/hỏng ⇒ báo lỗi rõ, không gửi.

### `~/.vflow/client.json` (tuỳ chọn, mọi khoá có mặc định)
```json
{ "repo": "~/Developer/vflow", "node": "/opt/homebrew/bin/node", "port": 7611 }
```
- `repo`: thiếu ⇒ nếu app nằm ở `<repo>/client/build/VFlow.app` thì dùng `<repo>`; không thì báo lỗi.
- `node`: thiếu ⇒ thử lần lượt `~/.local/bin/node`, `/opt/homebrew/bin/node`, `/usr/local/bin/node` (app GUI không có PATH của shell). Đặt sai ⇒ báo lỗi, **không** âm thầm dùng node khác.

## Phím nóng
- Event tap **chỉ nghe** (`listenOnly`): vflow không chặn hay sửa phím nào, ⌥ và Esc vẫn làm việc bình thường ở ứng dụng khác (Esc không bao giờ bị chặn tới ứng dụng đang focus).
- **Giữ ⌥ trái ≥ 200 ms** (không kèm ⌘/⌃/⇧/⌥ phải) ⇒ bắt đầu ghi (kiểu "giữ phím"); nhả ⇒ gửi. Chạm nhanh < 200 ms ⇒ bỏ qua hoàn toàn.
- **Đúp ⌥ trái** (hai lần chạm, mỗi lần < 200 ms, cách nhau ≤ 350 ms) ⇒ ghi **"khoá"** (hands-free): thanh trạng thái "Đang nghe (đã khoá, bấm ⌥ để xong, Esc để huỷ)"; không cần giữ phím nữa — bấm ⌥ một lần nữa (nhấn rồi nhả) ⇒ dừng và gửi.
- **Esc** ở BẤT KỲ kiểu ghi nào (giữ phím hay khoá, kể cả Command Mode) ⇒ huỷ ngay, không gửi, không ghi gì, hiện "Đã huỷ".
- Trong lúc chờ ngưỡng (trước 200 ms): bấm phím khác/bổ trợ khác/chuột ⇒ coi là tổ hợp (⌥←, ⌥-click, ký tự đặc biệt) và bỏ qua tới khi nhả ⌥.
- Trong lúc ghi: phím khác, ⌥ phải, ⌘, ⇧, fn, Caps Lock, bấm chuột ⇒ **huỷ** (bỏ âm thanh, hiện "Đã huỷ").
- Ghi tối đa 120 s rồi tự gửi (cảnh báo ở giây thứ 100 — ghi khoá hands-free có thể dài hơn, xem mục Micro/VAD bên dưới). Đang dịch thì không nhận lần ghi mới (không chồng). Mất sự kiện nhả phím ⇒ phát hiện qua trạng thái phím thật mỗi 50 ms (chỉ áp dụng kiểu "giữ phím" — ghi khoá không phụ thuộc trạng thái giữ ⌥); tap bị hệ thống tắt ⇒ bật lại và huỷ lần ghi; đang dịch quá 200 s ⇒ bỏ yêu cầu, về rảnh.

### Phím tắt tuỳ chỉnh (U4, Cài đặt › Giọng nói)
Phím "giữ để nói" và phím thứ hai cho Command Mode chọn được trong 4 phím bổ trợ đơn an toàn (⌥ trái mặc định, ⌥ phải, ⌃ trái mặc định cho Command Mode, ⌃ phải) — CỐ Ý loại ⇧/⌘ (dễ gõ nhầm khi dùng bình thường) và **bỏ Fn** (không đọc được ổn định qua CGEvent trên mọi loại bàn phím/máy — chưa kiểm chứng được trong môi trường dựng, không ghi mò). Hai phím trùng nhau ⇒ cảnh báo tiếng Việt ngay trong Cài đặt (Command Mode coi như tắt cho tới khi chọn lại khác nhau — không cấm lưu, chỉ cảnh báo). Nút "Đặt lại mặc định" trả về ⌥ trái/⌃ trái/⌥⌘V. Đổi **áp dụng ngay** cho lần ghi KẾ TIẾP — đổi giữa lúc đang ghi KHÔNG ảnh hưởng cử chỉ đang chạy (xem `VFlowCore.ActiveHotkeyConfig`, cấu hình chỉ được "chốt" lại khi máy trạng thái về rảnh). Lưu qua `VFlowCore.VFlowDefaults` (cô lập theo `VFLOW_HOME`). Logic phân loại phím vật lý→phím "giữ"/"Command Mode" nằm ở `VFlowCore.KeyClassifier.classify(config:)`/`HoldModifierKey`/`HotkeyKeyConfig` — tổng quát hoá từ bản cứng ⌥ trái/⌃ trái cũ, giữ NGUYÊN hành vi mặc định (test cũ không đổi).

### Chèn lại câu vừa rồi (U4, mặc định ⌥⌘V)
Một mục trong menu thanh trạng thái, menu Dock (CÙNG nguồn dữ liệu — xem mục Dock bên dưới) và phím tắt tổ hợp riêng (chọn giữa vài tổ hợp cố định ở Cài đặt › Giọng nói: ⌥⌘V/⌃⌘V/⌥⌘R — KHÔNG phải ô ghi phím tự do, để tránh ghi nhầm) ⇒ chèn lại văn bản cuối cùng đã đọc chính tả (dictation HOẶC Command Mode) vào ô đang focus bằng ĐÚNG đường chèn của dictation (`VFlowCore.ClipboardInserter`, cùng việc dò ô nhập/giữ clipboard khi lỗi). Lưu lịch sử đang BẬT ⇒ lấy từ lịch sử (mục mới nhất, còn đúng cả sau khi mở lại app); TẮT ⇒ chỉ nhớ trong RAM của phiên chạy hiện tại (không ghi đĩa, mất khi thoát app — xem `VFlowCore.LastSpokenText`). Không có câu nào ⇒ HUD "Chưa có câu nào". Bỏ qua im lặng (không làm gì) nếu đang ghi/dịch dở việc khác, để không chồng lên lượt đang chạy.

### Command Mode (⌥ trái + ⌃ trái)
Giữ ⌥ trái; nếu ⌃ trái được bấm trong **400 ms đầu** của lần giữ đó (dù đã qua ngưỡng 200 ms và bắt đầu ghi thường hay chưa) ⇒ chuyển sang Command Mode: thanh trạng thái "Đang nghe lệnh". ⌃ đến sau 400 ms hoặc phím khác ⇒ huỷ như tổ hợp phím thường (không vào Command Mode). Nhả ⌃ sớm không kết thúc Command Mode (chỉ là phím khởi động); chỉ nhả ⌥ (hoặc Esc) mới dừng/huỷ, giống kiểu "giữ phím" thường.

Luồng: (a) **lúc bắt đầu**, lấy đoạn đang chọn — thử Accessibility (`kAXSelectedTextAttribute` của phần tử focus) trước; không có (terminal, app tuỳ biến) thì thử sao chép tổng hợp ⌘C có kiểm soát: lưu nguyên clipboard, gửi ⌘C, chờ tối đa 250 ms thấy `changeCount` đổi thì đọc chuỗi rồi khôi phục clipboard; không đổi ⇒ không có đoạn chọn (xem `VFlowCore.SelectionCapture`, chạy song song với bước (b) để không mất đầu câu lệnh); (b) ghi âm lệnh, nhả ⇒ `POST /v1/transcribe?mode=normal` lấy chữ lệnh; (c) `POST /v1/command {instruction, selection, app}`; (d) thành công ⇒ dán kết quả bằng đúng đường dán ⌘V hiện có (đoạn chọn vẫn đang bôi đen nên sẽ bị thay thế), thanh trạng thái "Xong"; (e) lỗi (`cloud_disabled`, `rewrite_unavailable`, `timeout`, `bad_request`, lỗi engine khác) ⇒ hiện lỗi tiếng Việt rõ, **không dán gì, không sửa clipboard**. Lịch sử chỉ lưu **lệnh và kết quả** (`mode: "command:edit"` hoặc `"command:draft"`) — tuyệt đối không lưu đoạn đã chọn.

## Âm thanh và chèn chữ
- AVAudioEngine (tạo mới mỗi lần ghi, theo kịp đổi thiết bị) ⇒ downmix ⇒ 16 kHz Int16 LE trong RAM ⇒ `POST /v1/transcribe?mode=<chế độ>&app=<bundle id ứng dụng đang focus>` với `Content-Type: audio/L16; rate=16000; channels=1`. Không gửi `model` (engine chọn). **Không ghi âm thanh xuống đĩa**, không log văn bản.
- “Thử lại lần cuối”: giữ tối đa MỘT bản âm thanh trong RAM, tự xoá sau 5 phút hoặc khi có kết quả (kể cả “không nghe thấy gì”).
- Chèn: ghi `text` lên clipboard (kèm `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`), chờ 25 ms cho pasteboard công bố, rồi **LUÔN gửi ⌘V tổng hợp**, chờ 350 ms và khôi phục **nguyên** clipboard cũ (mọi mục, mọi kiểu) — trừ khi `changeCount` đổi (người dùng vừa sao chép thứ khác) thì không đè. **Nhả phím là chữ hiện luôn, người dùng KHÔNG phải bấm ⌘V.** Không còn dò "có ô nhập nào đang focus" bằng Accessibility: bản U4 từng chặn dán khi AX không báo được phần tử focus (Zalo, Chrome/Electron, app có AX không chuẩn…) và hiện "Đã chép — bấm ⌘V" — đó là hồi quy đã bị gỡ hẳn (`FocusedInputProbe` và `PasteOutcome.noFocusedInputTextKeptOnClipboard` đã xoá). Lý do DUY NHẤT để không dán là không có quyền Trợ năng (không gửi được ⌘V) ⇒ chữ để lại trên clipboard và HUD báo thiếu quyền (xem `VFlowCore.ClipboardInserter`/`PasteOutcome`). Nếu chính vflow (không phải app đích) đang ở phía trước lúc dán, vflow đưa lại app đích (app đang focus lúc bắt đầu ghi) lên trước rồi mới dán (`PasteTargetPolicy`/`PasteTargetActivator`); nếu người dùng chủ động chuyển sang app khác thì dán vào đó, không giật focus. **Giới hạn đã biết**: không phát hiện được trường hợp "ứng dụng đích lặng lẽ từ chối ⌘V" (cần so sánh giá trị ô nhập trước/sau, rủi ro báo sai cao hơn lợi ích).
- `silence:true` hoặc chữ rỗng ⇒ không chèn, hiện “Không nghe thấy gì”. Chế độ `email` mà viết lại lỗi ⇒ vẫn dán bản chưa viết lại và báo lỗi kèm mã.

### Micro, tự dừng khi im lặng, ghi âm dài (U4)
- **Chọn micro** (Cài đặt › Chung): danh sách thiết bị đầu vào thật (`AVCaptureDevice.DiscoverySession`) + "Mặc định hệ thống", lưu theo UID (không theo tên — tên có thể trùng). Thiết bị đã chọn biến mất (rút USB/Bluetooth…) ⇒ tự rơi về mặc định hệ thống và báo MỘT LẦN bằng HUD "Micro đã chọn không còn — dùng micro mặc định" (không lặp lại mỗi lần ghi sau đó — xem `VFlowCore.MicrophoneSelection`). Việc "ghim" `AVAudioEngine` vào đúng thiết bị dùng CoreAudio (`kAudioOutputUnitProperty_CurrentDevice`, `VFlow.AudioRecorder.setPreferredInputDevice`) — **CHƯA kiểm được bằng micro ngoài thật** trong môi trường dựng (không có micro USB/Bluetooth để đổi), chỉ kiểm được bằng build/test; chủ dự án nên tự thử đổi micro thật (xem MANUAL-TEST). Lỗi ở bước ghim bị bỏ qua ÊM (rơi về mặc định hệ thống), không chặn ghi âm.
- **Micro bị ngắt/đổi tuyến giữa lượt (Q2)**: `AVAudioEngineConfigurationChange` KHÔNG còn là lỗi chí mạng. Lỗi cũ: mỗi lần chọn micro cụ thể (ghim thiết bị) hoặc khi Bluetooth đổi tuyến, macOS bắn thông báo này ~0,3 s sau `engine.start()` và engine TỰ DỪNG (đo thật trên máy có tai nghe Bluetooth: bản cũ huỷ 6/6 lượt khi ghim thiết bị, 0/6 khi để mặc định) ⇒ thanh đỏ "Micro không dùng được: thiết bị micro thay đổi hoặc bị rút" dù không ai rút gì. Nay `VFlowCore.MicRecoverySession` (thuần, test bằng backend giả) kiểm TRẠNG THÁI THẬT mỗi khi có thông báo và mỗi 0,5 s: engine còn chạy + định dạng dùng được + còn khung mới ⇒ bỏ qua; engine chết/không có khung ⇒ dựng lại ÊM (dừng-chạy lại cùng engine → dựng engine mới ghim thiết bị đã chọn → dựng engine mới theo mặc định hệ thống, tối đa 6 lần mỗi lượt), mẫu PCM đã thu GIỮ NGUYÊN kể cả khi tần số lấy mẫu đổi giữa chừng (`RecordingBuffer`). Chỉ khi mọi bước hỏng: đã thu ≥ 0,5 s ⇒ GỬI ĐI + HUD nhắc ngắn; chưa có gì ⇒ báo đỏ với đúng nguyên nhân ("micro bị ngắt giữa chừng (tên thiết bị)" / "không mở được micro (…)"). Micro đã chọn không dùng lại được ⇒ rơi về mặc định + nhắc nhẹ MỘT lần (không phải lỗi đỏ) và cập nhật lựa chọn nếu thiết bị thật sự đã biến mất. `installTap` dùng `format: nil` vì truyền định dạng đọc từ trước làm AVFAudio ném NSException "format mismatch" (Swift không bắt được ⇒ sập app) khi tuyến vừa đổi. Lượt thành công xoá "Lỗi gần nhất" (`LastErrorPolicy`). **Chưa kiểm được** bằng thao tác vật lý (rút tai nghe giữa câu, app khác chiếm micro) — xem MANUAL-TEST mục M.
- **Tự dừng khi im lặng** (CHỈ ghi khoá hands-free — đúp ⌥, KHÔNG áp dụng cho kiểu giữ phím): VAD mức năng lượng đơn giản, ngưỡng thích nghi hai tốc độ theo nhiễu nền (thích nghi CHẬM khi đang coi là có tiếng nói — nói liên tục/dài không tự kéo ngưỡng lên rồi hiểu lầm giữa câu; NHANH khi đang im lặng — bắt kịp nhiễu nền thật; xem `VFlowCore.VoiceActivityDetector`). Thời gian im lặng để tự dừng cấu hình ở Cài đặt › Chung (`silence_stop_seconds` qua `/v1/settings` hiện có, 0 = tắt hẳn, 1–60 giây; khoá vắng mặt ở engine cũ ⇒ coi là 0, không lỗi). HUD hiện đếm ngược (mỗi giây, từ lúc còn ≤5s) trước khi tự dừng+gửi — giống hiệu ứng bấm phím giữ một lần nữa.
- **Ghi âm dài** (hands-free): đọc `max_audio_seconds` từ `/healthz` nếu engine có báo (chưa có trong contract hiện tại ⇒ dùng mặc định 120s, không suy đoán — xem `VFlowCore.RecordingLimit`); có báo thì dùng giá trị đó, kẹp trong [120, 1200] giây. Cảnh báo "còn khoảng 30 giây sẽ tự gửi" (khác mốc 20s của kiểu giữ phím 120s cố định) rồi tự dừng+gửi khi hết giới hạn, không mất dữ liệu đã ghi.

## Quyền macOS (đúng những gì cần)
| Quyền (System Settings › Quyền riêng tư & Bảo mật) | Vì sao | API kiểm / xin |
|---|---|---|
| **Micro** | ghi giọng nói | `AVCaptureDevice.authorizationStatus/requestAccess(.audio)`; Info.plist `NSMicrophoneUsageDescription` |
| **Theo dõi đầu vào** (Input Monitoring) | event tap nghe phím toàn cục (sự kiện bàn phím của ứng dụng khác) | `CGPreflightListenEventAccess` / `CGRequestListenEventAccess` |
| **Trợ năng** (Accessibility) | gửi ⌘V tổng hợp bằng `CGEvent.post` | `CGPreflightPostEventAccess` / `CGRequestPostEventAccess` |

Không cần: Ghi màn hình, Tự động hoá (Apple Events), đọc nội dung cửa sổ qua AX. Nguồn: tài liệu Apple cho `CGPreflightListenEventAccess`/`CGRequestListenEventAccess` (Input Monitoring, macOS 10.15+) và `CGPreflightPostEventAccess`/`CGRequestPostEventAccess` (gửi sự kiện, hiện ở danh sách Trợ năng). Đã quan sát thực tế: bản dựng mới chưa được cấp thì `CGPreflightListenEventAccess` trả `false` và app báo “Thiếu quyền Theo dõi đầu vào”; **chưa** kiểm toàn bộ luồng cấp quyền thật (việc của chủ dự án — xem `MANUAL-TEST.md`).

- Khi khởi động app kiểm cả 3 quyền; thiếu quyền nào thì menu có dòng “Thiếu quyền … — mở Cài đặt…” mở đúng trang (`x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone|Privacy_ListenEvent|Privacy_Accessibility`). Event tap chỉ được tạo khi đã có Input Monitoring; app thử lại mỗi 3 s nên thường không cần mở lại (nếu vẫn không nhận phím thì thoát và mở lại).
- **Chữ ký**: TCC gắn quyền với chữ ký. Bản **ký ad-hoc** (`-s -`, khi chưa chạy `make-signing-identity.sh`) không có danh tính ổn định ⇒ mỗi lần chạy lại `build-app.sh` có thể tạo chữ ký mới ⇒ macOS có thể đòi cấp lại (bật/tắt lại vflow trong danh sách). Bản **ký ổn định** (danh tính tự ký "vflow Local Signing", xem mục Chữ ký bên dưới) giữ cùng một chứng chỉ qua các lần dựng ⇒ quyền thường được giữ nguyên (không đảm bảo tuyệt đối — macOS vẫn có thể đòi cấp lại nếu đổi `CFBundleIdentifier`/đường dẫn cài đặt). vflow không bao giờ tự sửa/xoá cơ sở dữ liệu TCC.

## Dock, menu ứng dụng, biểu tượng thanh menu
Từ M4a, `NSApp.setActivationPolicy(.regular)`: có biểu tượng Dock, hiện trong ⌘-Tab, và có menu ứng dụng đầy đủ ("vflow" — Giới thiệu, Cài đặt… ⌘,, Ẩn ⌘H, Thoát ⌘Q; "Cửa sổ"; "Trợ giúp" mở `client/README.md` nếu chạy từ repo, không thì mở cửa sổ chính). Bấm biểu tượng Dock hoặc `open client/build/VFlow.app` lần nữa khi app đang chạy ⇒ **không** mở tiến trình thứ hai, chỉ đưa cửa sổ chính lên trước (`applicationShouldHandleReopen`).

Biểu tượng thanh menu (`org.aios.vflow`) vẫn còn nhưng giờ chỉ là PHỤ — có công tắc "Hiện biểu tượng trên thanh menu" ở Cài đặt › Chung (mặc định bật); ảnh TEMPLATE đơn sắc, macOS tự vẽ trắng/đen theo nền thanh menu (xem mục Logo). `item.autosaveName` được đặt cố định (`org.aios.vflow.statusItem`, từ U4) để macOS CÓ CƠ HỘI nhớ vị trí biểu tượng qua các lần chạy — KHÔNG tự đặt vị trí ưu tiên ban đầu (cơ chế "NSStatusItem Preferred Position" không công khai, chưa kiểm chứng được an toàn trong môi trường này nên bỏ, đúng như cho phép ở yêu cầu).

**Dò biểu tượng bị che (U4)**: trên thanh menu chật (nhiều mục) hoặc dưới notch của MacBook, macOS có thể tự ẩn/che biểu tượng mà không báo gì — vflow tự dò bằng cách so `item.button?.window?.frame` với `NSScreen.main?.frame`/`auxiliaryTopLeftArea`/`auxiliaryTopRightArea` (hàm thuần `VFlowCore.MenuBarOcclusion.isOccluded`, test được bằng toạ độ giả — đã dùng ĐÚNG số đo thật trên máy chủ dự án: notch x=918–1138, biểu tượng vflow ở x≈1118), chạy lại mỗi khi tạo biểu tượng và mỗi khi `NSApplication.didChangeScreenParametersNotification` bắn (đổi màn hình/độ phân giải). Bị che ⇒ tab Tổng quan hiện thẻ nhắc đóng được, NHỚ THEO NGÀY (không đóng vĩnh viễn — hoàn cảnh đổi mỗi ngày, xem `VFlowCore.MenuBarOcclusionReminder`): "Biểu tượng vflow đang nằm sau notch hoặc thanh menu đầy. Thoát bớt ứng dụng có biểu tượng thanh menu, rồi giữ ⌘ và kéo biểu tượng vflow sang sát bên phải; hoặc dùng menu ở Dock." kèm nút mở thẳng Cài đặt › Chung.

Cách điều khiển CHÍNH không phụ thuộc biểu tượng thanh menu: cửa sổ **"vflow"** (Dock, ⌘-Tab, menu ứng dụng) VÀ **menu Dock** (chuột phải/giữ biểu tượng Dock của vflow) — từ U4, menu Dock có CÙNG các mục với menu thanh trạng thái (trạng thái, chế độ hiện tại có dấu tích, chuyển chế độ, "Chèn lại câu vừa rồi", "Mở cửa sổ vflow", "Cài đặt…", Thoát…), dựng từ CÙNG một hàm (`StatusMenu.populate(_:model:controller:)`, xem `AppDelegate.applicationDockMenu`) nên không bao giờ lệch nhau hay nhân đôi logic.

**Đóng cửa sổ chính (nút đỏ) KHÔNG thoát app** — ghi âm bằng phím nóng vẫn hoạt động, engine con vẫn chạy; cửa sổ tự ghi chú điều này ở chân mỗi tab. Thoát hẳn bằng **⌘Q** hoặc menu "vflow › Thoát vflow" (cũng có ở Cài đặt › Chung). Nếu cửa sổ bị đóng và cần mở lại: bấm Dock, `open client/build/VFlow.app`, hoặc menu thanh trạng thái "Mở cửa sổ vflow".

## Cửa sổ chính "vflow"
Một cửa sổ (`.titled`, đổi cỡ được, mặc định ≈960×680, tối thiểu ≈800×560, nhớ kích thước/vị trí — cô lập theo `VFLOW_HOME` từ U2, xem `VFlow.WindowFramePersistence`), thanh công cụ thống nhất (tiêu đề mục đang chọn — MỘT nơi duy nhất, nội dung không lặp lại tiêu đề), thanh bên có logo+tên "vflow" ở đầu rồi 5 mục xếp 2 nhóm — **Sử dụng** (Tổng quan, Thống kê [V2], Lịch sử), **Cá nhân hoá** (Từ điển, Snippets). **Từ U2**: mục đang chọn ở thanh bên KHÔNG dùng `List(selection:)` nữa (`NavigationSplitView`/`listStyle(.sidebar)` luôn tô màu nhấn HỆ THỐNG, không có API đổi) — tự vẽ (`VFlow.SidebarRow`, nút phẳng + viên thuốc cam thương hiệu khi chọn), vẫn điều khiển được bằng bàn phím (Tab/Space, ⌘1…⌘5)/VoiceOver, huy hiệu cam nhỏ ở "Tổng quan" khi có quyền macOS còn thiếu. Lần đầu mở, một thẻ nhỏ nhắc "Đóng cửa sổ không thoát vflow…" hiện một lần (đóng được, nhớ bằng `hasSeenCloseHint`) thay cho dòng chân trang cố định của U1. Phím tắt ⌘1…⌘5 chuyển mục (theo thứ tự trên); ⌘, mở cửa sổ Cài đặt (riêng, xem mục bên dưới). Màu nhấn cam thương hiệu #ED6300 (`Theme.accent`, `client/Sources/VFlow/Theme.swift`) dùng cho công tắc/mục chọn/nút chính; thẻ (`cardBackground()`) từ U2 dùng `controlBackgroundColor` đặc + viền `separatorColor` + bóng nhẹ (không còn `.regularMaterial` — không đủ phân biệt với nền cửa sổ ở giao diện TỐI, đã kiểm bằng ảnh chụp).

**Tổng quan** — bảng điều khiển (U1), lấy từ CÙNG MỘT mô hình thuần `StatusModel` (VFlowCore) với menu thanh trạng thái nên hai nơi không bao giờ nói khác nhau; nội dung và chữ hiển thị quyết định bởi các hàm thuần có test trong `VFlowCore/DesignSystem.swift` (`HeroStatusDecision`, `ModelReasonText`, `PermissionsProgress`, `TodayStats`, `ModeCloudLabel`):
- **Thẻ trạng thái lớn** đầu trang: "Sẵn sàng. Giữ ⌥ trái để nói", hoặc trạng thái vấn đề (thiếu quyền/đang khởi động engine/lỗi) kèm nút hành động phù hợp ("Cấp quyền…"/"Khởi động lại engine"/"Thử lại lần cuối"); từ U2 có biểu tượng + nền nhấn nhẹ THEO TRẠNG THÁI (cam thương hiệu khi sẵn sàng, cam cảnh báo khi thiếu quyền, đỏ khi lỗi); **cảnh báo xung đột phím** riêng nếu phát hiện ứng dụng đọc chính tả khác đang chạy (danh sách mặc định trong `VFlowCore.ConflictConfig`, đầu tiên là `com.sonpiaz.haynoi`/Haynoi); thẻ lỗi gần nhất có thể đóng.
- **Thẻ phím tắt** dạng keycap: Giữ ⌥ để nói · Bấm đúp ⌥ để khoá ghi âm · Esc để huỷ · Giữ ⌥+⌃ để ra lệnh (Command Mode) · nói "nhấn enter" cuối câu.
- **Thẻ chế độ**: 6 chế độ dạng LƯỚI 2 cột (từ U2, gọn hơn danh sách dọc của U1), icon + mô tả ngắn + nhãn "Trong máy"/"Gửi chữ qua 9Router" (`ModeCloudLabel`, lấy từ `DictationMode.sendsTextToCloud` — nguồn duy nhất, không viết lại tay), viền cam rõ khi đang chọn.
- **Thẻ quyền**: gọn "Đã cấp n/3" kèm dấu tích khi đủ; mở rộng từng dòng + nút "Cấp quyền…" khi thiếu.
- **Thẻ "Hôm nay"**: số câu, số từ, thời gian nói — tính THUẦN từ lịch sử trong ngày (`TodayStats.summarize`, có test); lịch sử tắt ⇒ "Lịch sử đang tắt" (không hiện số 0 giả).
- **Thẻ nhắc biểu tượng thanh menu bị che** (U4, chỉ hiện khi bị che và chưa đóng HÔM NAY — xem mục Dock) — đóng được, nhớ theo ngày, có nút mở thẳng Cài đặt › Chung.
- Mục **"Hệ thống"** thu gọn (`DisclosureGroup`): engine + danh sách model với chữ thân thiện thay mã kỹ thuật (`ModelReasonText.friendly`: `not_downloaded`→"Chưa tải về", `missing_token`→"Chưa có khoá truy cập", `tunnel_down`→"Chưa kết nối", `loading`→"Đang tải", `loaded`→"Sẵn sàng", mã lạ→"(mã đó)" — không bao giờ im lặng), "Thử lại lần cuối", "Khởi động lại engine", "Mở thư mục dữ liệu".

**Lịch sử** — các câu đã đọc chính tả, **gom theo ngày** từ U2 ("Hôm nay"/"Hôm qua"/ngày đầy đủ — `VFlowCore.HistoryGrouping`, hàm thuần có test cho biên nửa đêm), mới nhất trên cùng trong mỗi nhóm; mỗi dòng có biểu tượng ứng dụng đích THẬT (`NSWorkspace.icon(forFile:)` theo bundle id, dự phòng biểu tượng chung khi không rõ/app đã gỡ — xem `VFlow.AppIconResolver`), giờ, chip chế độ, văn bản. CHỈ lưu văn bản (`text_raw`, `text`, mode, app bundle id, model, audio_ms, timings) — **tuyệt đối không có âm thanh**; mục Command Mode lưu dạng `mode: "command:edit"|"command:draft"`, `text_raw` = lệnh đã nói, `text` = kết quả — **không bao giờ lưu đoạn đang chọn**. Lưu `<VFLOW_HOME>/history.jsonl` (JSONL, quyền 0600, ghi nối nguyên tử + tự dọn giữ tối đa 500 mục/30 ngày, dòng hỏng bị bỏ qua và đếm chứ không làm sập — xem `VFlowCore.HistoryStore`). Tìm kiếm ở thanh công cụ (`.searchable`), menu chuột phải (Sao chép, Sửa…, Thêm vào từ điển…, Xoá) + ⌘C cho mục đang chọn; "Sửa…" mở hộp sửa văn bản cuối, Lưu ⇒ `POST /v1/corrections` ⇒ hiện gợi ý `{term, spoken}`, CHỈ ghi vào từ điển khi người dùng bấm xác nhận từng gợi ý (không gợi ý thì nói rõ "Không có gợi ý", không tự dán lại văn bản đã sửa vào đâu cả); "Thêm vào từ điển…" (U2) mở sheet thêm nhanh, tiền điền cách nói bằng câu đã chọn. Xoá một mục, "Xoá toàn bộ lịch sử…" (xác nhận). Công tắc "Lưu lịch sử" ở Cài đặt › Dữ liệu & Riêng tư (mặc định bật; tắt ⇒ không ghi mục mới, không xoá mục cũ) — trạng thái rỗng phân biệt rõ "Chưa có câu nào" (gợi ý giữ ⌥) và "Lịch sử đang tắt" (`ContentUnavailableView`). Kết quả lỗi/im lặng không bao giờ vào lịch sử.

**Từ điển** — đọc `GET /v1/dictionary`, thêm/sửa/xoá qua `PUT /v1/dictionary` kiểu **đọc-sửa-ghi** (đọc lại ngay trước khi ghi, xem `VFlowCore.DictionaryOrchestration`, để không đè thay đổi của engine/cửa sổ khác giữa chừng). Thanh công cụ có nút "+", tìm kiếm (`.searchable`), sắp xếp A–Z/Dùng nhiều (`VFlowCore.ListSorting`, dùng chung với Snippets); mỗi dòng hiện "cách nói" dạng chip (`VFlow.SpokenChips`) + số lần dùng. Sheet thêm/sửa (từ U2) dùng `Form` grouped, kiểm hợp lệ NGAY KHI GÕ bằng CHÍNH luật engine (`VFlowCore.DictionaryFormValidation`, áp `DictionaryValidation.validate` lên danh sách SẼ CÓ sau khi lưu — không viết luật riêng, nên không lệch với contract: term trùng/quá dài/rỗng, spoken rỗng… đều có thông điệp tiếng Việt), nút Lưu vô hiệu khi còn lỗi. Trạng thái rỗng gợi ý ví dụ cụ thể ("Thêm 'deploy' với cách nói 'đi plôi'"). Engine không chạy ⇒ nói rõ bằng chữ đỏ, KHÔNG hiện danh sách rỗng giả.

**Snippets** — đọc `GET /v1/snippets`, thêm/sửa/xoá qua `PUT /v1/snippets` kiểu đọc-sửa-ghi giống Từ điển (xem `VFlowCore.SnippetOrchestration`). Mỗi mục: trigger, xem trước NHIỀU DÒNG nội dung (tối đa 2 dòng hiện, mở sheet để xem đủ), số lần dùng; cùng thanh công cụ "+"/tìm kiếm/sắp xếp và sheet `Form` kiểm hợp lệ ngay khi gõ (`VFlowCore.SnippetFormValidation`, áp `SnippetValidation.validate`) như Từ điển. Trạng thái rỗng gợi ý ví dụ ("link lịch hẹn → https://…"). Dòng hướng dẫn: nói đúng cả câu bằng trigger, hoặc "chèn \<trigger\>" trong câu.

## Cửa sổ Cài đặt (từ U1)
CỬA SỔ RIÊNG chuẩn macOS (`SettingsWindow.swift`), KHÔNG còn là mục trong thanh bên cửa sổ chính — mở bằng ⌘, hoặc menu "vflow › Cài đặt…"; `AppController.openSettingsWindow(tab:)` là một singleton, gọi lại chỉ đưa lên trước + đổi mục. **Từ Q1**: thanh tab chỉ còn **5 mục** (`SettingsCategory` = `VFlowCore.SettingsPane`) thay cho 8 mục cũ vốn chen một hàng nên 6/8 nhãn bị cắt chữ; cửa sổ mặc định 780×600, rộng tối thiểu 720 pt, kéo giãn được; mỗi mục là một `Form` cuộn được gồm nhiều `Section` có tiêu đề, chú thích dài tự xuống dòng. Tên mục cũ vẫn được nhận (`hotkeys`→Giọng nói, `cloud`→Nâng cao, `historyPrivacy`→Dữ liệu & Riêng tư) cho cờ `--open-settings-tab`, `--render-offscreen caidat:<mục>` và `openSettingsWindow(tab:)`:
- **Chung** — chế độ mặc định (`ModeSection`, cùng nguồn `DictationMode` với Tổng quan), Bật khi đăng nhập, Hiện cửa sổ "vflow" khi mở app, Hiện biểu tượng trên thanh menu, giao diện Sáng/Tối, thanh ghi âm (vị trí/cỡ), chọn micro, nút Thoát vflow.
- **Giọng nói** — phím tắt (phím "giữ để nói", phím thứ hai Command Mode, tổ hợp "Chèn lại câu vừa rồi", cảnh báo trùng phím, "Đặt lại phím tắt về mặc định"), dấu câu bằng giọng, nói nhỏ, xem chữ chạy trực tiếp, ký hiệu theo ngữ cảnh, tự dừng khi im lặng, giọng điệu, "Nhấn Enter bằng giọng" (`actions_enabled`).
- **Ứng dụng** — luật theo ứng dụng (`app_rules`).
- **Dữ liệu & Riêng tư** — lịch sử (công tắc "Lưu lịch sử" + "Xoá toàn bộ lịch sử…"), riêng tư, thống kê, "Lưu âm thanh để nghe lại" (tắt mặc định), xuất/nhập, chẩn đoán.
- **Nâng cao** — đám mây 9Router (giữ nguyên hành vi M4a): công tắc "Cho phép gửi chữ qua 9Router" (`cloud_llm`), ô "Model" (`llm_model`, trống = chưa đặt, kèm cảnh báo Gọn/Thư/Command Mode sẽ không chạy), "Thời gian chờ" (`llm_timeout_ms`, 1–30 s) — đọc/ghi qua `GET/PUT /v1/settings`, hiệu lực ngay, lỗi `bad_request` hiện tiếng Việt, "Đang chờ engine khởi động…" khi chưa sẵn sàng; độ trễ bắt đầu ghi; thông tin kỹ thuật (đường dẫn dữ liệu hiện dùng — tôn trọng `VFLOW_HOME` — + "Mở thư mục dữ liệu", phiên bản vflow).

**Lối vào nút Cài đặt (U4)** — bốn chỗ, tất cả mở CÙNG cửa sổ singleton trên (không nhân bản): (a) nút bánh răng cố định ở CHÂN thanh bên cửa sổ chính (kèm gợi ý "⌘,"); (b) nút bánh răng ở thanh công cụ cửa sổ chính, phía phải (`ToolbarItem(placement: .primaryAction)`); (c) mục "Cài đặt…" trong menu thanh trạng thái VÀ menu Dock (cùng nguồn, xem mục Dock); (d) nút "Mở Cài đặt › Chung" trong thẻ nhắc "biểu tượng thanh menu bị che" ở Tổng quan — ví dụ cụ thể cho yêu cầu "thẻ vấn đề dẫn tới đúng tab liên quan"; các vấn đề KHÁC (engine lỗi, thiếu quyền…) đã có nút hành động riêng từ trước (Khởi động lại engine/Cấp quyền…) nên không thêm liên kết Cài đặt trùng lặp ở đó.

### Chế độ đọc chính tả (6)
| Chế độ | Trong máy/Đám mây | Mô tả |
|---|---|---|
| Tự động | trong máy | Chọn theo `auto.apps` (mặc định CHỈ chọn chế độ trong máy — bất biến 10: terminal/IDE→dev, thư/nhắn tin→clean, còn lại→normal); tự ánh xạ sang tidy/email được nhưng không phải mặc định |
| Thường | trong máy | STT + từ điển |
| Làm sạch | trong máy | + bỏ từ đệm, sửa dấu câu cơ bản (quy tắc, không LLM) |
| **Gọn** | **đám mây (9Router)** | + snippets, quy tắc lập trình, LLM làm gọn (thêm dấu câu, bỏ từ đệm, tự sửa giữa câu); guard chặn LLM thêm nội dung lạ |
| **Lập trình** | trong máy | + đọc kiểu lập trình thuần quy tắc ("gạch dưới"→`_`, snake_case, camelCase…), không gửi gì ra ngoài |
| Thư | **đám mây (9Router)** | STT + từ điển + viết lại thành thư chuyên nghiệp qua 9Router |

Lỗi/quá giờ/tắt đám mây ở Gọn/Thư ⇒ vẫn dán bản đã qua từ điển (+ `clean` bằng quy tắc ở Gọn), báo lỗi rõ kèm mã (`guard_rejected`, `cloud_disabled`…) — không bao giờ báo thành công giả.

## Thanh trạng thái nổi và menu
- NSPanel không viền, không lấy focus, bỏ qua chuột, nổi trên mọi Space/toàn màn hình, giữa đáy màn hình có con trỏ chuột (phía trên Dock); từ U2 là viên thuốc `.regularMaterial` (trước là nền đen đặc) + chuyển cảnh spring. Logo-mark cạnh chữ trạng thái; 6 trạng thái: "Đang nghe" (`mic.fill` + sóng âm 7 vạch ĐỘNG theo mức, vạch giữa cao nhất — `VFlowCore.WaveformMeter`, có test biên/Reduce Motion), "Đang nghe (đã khoá…)" (ghi hands-free, nhắc rõ bằng chữ "bấm ⌥ để xong, Esc để huỷ"), "Đang nghe lệnh" (Command Mode, `command`), "Đang dịch" (vòng xoay `ProgressView`, từ U2 thay icon tĩnh), "Xong" (`checkmark.circle.fill`), "Lỗi: …" (`exclamationmark.triangle.fill`); thông báo ngắn "Đã huỷ"/"Không nghe thấy gì" (`info.circle`); cảnh báo "còn ~20s" ở giây thứ 100 rồi tự quay lại trạng thái đang nghe. Chữ 13 pt, tôn trọng Reduce Motion (sóng âm TĨNH nhưng vẫn đổi theo mức, không hoạt ảnh), nhãn VoiceOver và thông báo VoiceOver khi đổi trạng thái (trừ lúc đang nghe). `--demo-overlay ghi|khoa|dich|xong|loi` chụp đủ 5 trạng thái.
- Menu bar (từ U1): biểu tượng là ảnh TEMPLATE đơn sắc (đen+alpha, `menubar-mark-18-template{,@2x,@3x}.png`, `NSImage.isTemplate = true`) — macOS tự vẽ TRẮNG trên thanh menu tối, ĐEN trên thanh menu sáng; không có bundle đóng gói thì rơi về SF Symbol (cũng `isTemplate`). Trạng thái (nghe/dịch/lỗi…) phân biệt bằng HÌNH huy hiệu góc dưới-phải vẽ thêm vào chính ảnh template (`VFlow.BrandIcon.statusImage`, xem mục Logo): chấm đặc (đang nghe), vòng (đang nghe lệnh), ngôi sao lấp lánh (đang dịch), tam giác cảnh báo khoét dấu chấm than (lỗi/thiếu quyền/xung đột) — KHÔNG dựa vào màu; tooltip/nhãn trợ năng luôn mô tả đúng trạng thái bằng chữ. Từ U2, menu có dòng trạng thái + biểu tượng ĐẦU menu, các mục nhóm theo tiêu đề (`NSMenuItem.sectionHeader`: "Cần xử lý", "Chế độ", "Khác"), dấu tích (`.state = .on`) cho chế độ hiện tại, biểu tượng SF Symbols cho hầu hết mục: "Mở cửa sổ vflow"; trạng thái engine; cảnh báo xung đột phím (nếu có); lỗi gần nhất (đầy đủ); quyền thiếu; Chế độ (đủ 6, nhớ qua `VFlowCore.VFlowDefaults` — `.standard` nếu không có `VFLOW_HOME`); Model (từ `/healthz`, model `loaded:false` hiện kèm lý do); Thử lại lần cuối; Khởi động lại engine (khi đã bỏ cuộc); Bật khi đăng nhập (SMAppService); Mở thư mục dữ liệu (`~/.vflow`); "Hướng dẫn cấp quyền…" (mở cửa sổ "vflow"); Thoát. Biểu tượng thanh menu TỰ THÂN (không phải nội dung menu) vẫn là template trắng/đen của U1, không đổi. Công tắc ẩn/hiện biểu tượng này nằm ở Cài đặt › Chung (cửa sổ Cài đặt riêng, không còn ở cửa sổ chính).

## Logo
`client/Resources/branding/logo-main.png` (tròn cam, chữ V đen, 1024², do chủ dự án cung cấp, KHÔNG sửa) ⇒ `scripts/make-icon.sh` gọi `scripts/make-icon.swift` (CoreGraphics) để DỰNG LẠI biểu tượng app thành một ô bo góc kiểu macOS (squircle) lấp đầy khung thay vì vòng tròn trên nền trong suốt: lấy mẫu màu cam (trung vị pixel đặc, không dính chữ V) từ logo-main.png, tách chữ V + vạch sóng + chấm thành mặt nạ alpha theo độ tối, vẽ cả hai lên một squircle MỚI (824/1024, viền cong đo thực tế từ một icon hệ thống chuẩn — không phải siêu elip xấp xỉ, xem chú thích `profileFraction` trong make-icon.swift) để tránh macOS tự thêm "tấm nền xám" phía sau (NSWorkspace coi icon không đúng hình chuẩn là icon "kiểu cũ" cần được mặc thêm nền). Ảnh gộp 1024² lưu ở `client/Resources/branding/appicon-1024.png` (để xem/kiểm), rồi `sips -z`/`iconutil -c icns` ra `client/Resources/AppIcon.icns` (biểu tượng Dock/Finder/Cmd-Tab/Giới thiệu, qua `CFBundleIconFile` trong Info.plist).

`client/Resources/branding/logo-mark.png` (chữ V cam trên nền trong suốt, 1024², KHÔNG sửa) ⇒ hai bộ ảnh dẫn xuất:
- `sips -z` ra `menubar-mark-18{,@2x,@3x}.png` (18/36/54 px, CÓ MÀU cam) — dùng cho đầu cửa sổ chính (sidebar header, ~22pt) và cạnh chữ trên thanh trạng thái ghi âm nổi (`VFlow.BrandIcon.menuBarMark`/`headerMark`, nạp từ `Bundle.main.resourcePath`), nơi màu thương hiệu có ý nghĩa.
- `scripts/make-icon-template.swift` (CoreGraphics, từ U1) ra `menubar-mark-18-template{,@2x,@3x}.png` (18/36/54 px, ĐƠN SẮC đen+alpha: mọi điểm ảnh có alpha>0 bị ép RGB=(0,0,0), có test resource kiểm điều này) — dùng DUY NHẤT cho biểu tượng THANH MENU THẬT (`BrandIcon.menuBarTemplateMark`/`statusImage`, `isTemplate = true`) để macOS tự vẽ trắng/đen theo nền thanh menu. Trạng thái không dựa vào màu: `BrandIcon.statusImage(badge:)` vẽ thêm một huy hiệu ~7pt ở góc dưới-phải trực tiếp lên alpha của ảnh template (chấm đặc/vòng/sao lấp lánh/tam giác cảnh báo — xem `MenuBarBadge`), cộng tooltip/nhãn trợ năng luôn mô tả bằng chữ (`StatusMenu.iconState`). Kiểm bằng ảnh: dựng cửa sổ thử `--demo-icon` (KHÔNG chụp thanh menu thật vì có dữ liệu cá nhân) hiện cả 5 trạng thái trên nền đen/trắng side-by-side.

Chạy lại `scripts/make-icon.sh` khi đổi logo (sinh cả ảnh màu lẫn ảnh template); `build-app.sh` chỉ COPY các tệp sinh ra (không tự sinh).

## Chữ ký
`client/scripts/lib-signing.sh` (dùng chung, nạp bằng `source` trong `build-app.sh`/`install-app.sh`/`make-signing-identity.sh`) dò **3 trạng thái** của danh tính "vflow Local Signing" trong keychain — đo thật trên keychain tạm, không phải suy đoán:
- **none** — chưa có chứng chỉ nào tên này.
- **untrusted** — đã có chứng chỉ+khoá trong keychain (`security find-identity -p codesigning`, KHÔNG `-v`, thấy kèm `CSSMERR_TP_NOT_TRUSTED`) nhưng hệ thống CHƯA tin cậy nó cho ký mã ⇒ `security find-identity -v -p codesigning` báo "0 valid identities found" và `codesign -s "vflow Local Signing"` báo "no identity found" (exit 1) — **không ký được**, dù chứng chỉ đã tồn tại.
- **valid** — đã tin cậy, `-v` thấy, ký được ngay.

`none` và `untrusted` đều khiến `build-app.sh` ký **ad-hoc** (`-s -`, mất quyền macOS mỗi lần dựng lại — xem mục Quyền macOS), nhưng thông báo khác nhau: `untrusted` nhắc rõ chỉ cần chạy lại `--yes` để THÊM tin cậy (không cần tạo chứng chỉ mới), còn `none` cần tạo từ đầu.

`client/scripts/make-signing-identity.sh --yes`:
1. Tạo chứng chỉ **tự ký** tên cố định "vflow Local Signing" (RSA 2048, hạn 10 năm, `extendedKeyUsage=codeSigning`) bằng **`/usr/bin/openssl`** (LibreSSL của macOS — **không** dùng `openssl` trong PATH: bản Homebrew hiện tại xuất `.p12` bị `security import` từ chối "MAC verification failed", đã tự kiểm thật trước khi viết script).
2. Nhập vào keychain (`-T /usr/bin/codesign`).
3. **Tin cậy** chứng chỉ cho ký mã (`security add-trusted-cert -r trustRoot -p codeSign`) — bước này hiện hộp thoại đổi Certificate Trust Settings, **cần chủ dự án xác nhận trực tiếp** (có thể là hộp thoại mật khẩu keychain thứ hai, riêng với hộp thoại ở bước nhập).

Idempotent theo đúng 3 trạng thái trên (xem chú thích đầu file); `--dry-run` chỉ in các lệnh sẽ chạy (gồm cả bước tin cậy), không đổi gì; `--remove [--yes|--dry-run]` xoá chứng chỉ+khoá và bỏ tin cậy (`security delete-identity -t`), cũng idempotent. Lần ký đầu sau khi có danh tính hợp lệ, macOS có thể hỏi thêm "codesign muốn dùng khoá riêng của bạn" — bấm **"Luôn cho phép"**.

Biến môi trường `VFLOW_SIGN_KEYCHAIN` (đổi keychain đích) và `VFLOW_SIGN_SKIP_TRUST=1` (bỏ bước tin cậy) chỉ dùng cho test tự động trên keychain tạm — không dùng khi chạy `--yes` thật.

Có danh tính ở trạng thái `valid` ⇒ `build-app.sh`/`bundle-engine.sh` tự dùng nó để ký cả bundle lẫn nhị phân lồng nhau (node, `*.node`, `*.dylib`), giữ **cùng một chữ ký** qua các lần dựng ⇒ quyền macOS thường được giữ.

Xem chữ ký đang dùng và có giữ được quyền không:
```sh
codesign -dvvv client/build/VFlow.app 2>&1 | grep -i "authority\|identifier\|designated"
codesign -dr- client/build/VFlow.app     # build-app.sh tự in dòng này; còn "cdhash" ⇒ vẫn ad-hoc, ký "ổn định" chưa có tác dụng
codesign -d --entitlements - client/build/VFlow.app   # (vflow không khai entitlement nào — không sandbox, không hardened runtime)
```
`Authority=vflow Local Signing` (ký ổn định) hoặc `Authority=-` không xuất hiện/`adhoc` (ký ad-hoc) cho biết đang dùng kiểu nào; `designated requirement` ổn định (dựa trên chứng chỉ, không có `cdhash`) là điều kiện để TCC coi các lần dựng là "cùng một app".

## Rủi ro đã biết
- **Va chạm ⌥**: vì tap chỉ nghe, ký tự gõ bằng ⌥ (å, ∫, “…) vẫn vào ứng dụng như thường. Nếu giữ ⌥ ≥ 200 ms rồi mới bấm phím (⌥← chậm, ⌥-kéo chuột) thì micro bật thoáng qua rồi huỷ (“Đã huỷ”), chỉ báo micro màu cam có thể nháy. Giữ ⌥ một mình (ví dụ chờ để ⌥-click) sẽ bắt đầu ghi.
- Ghi bắt đầu sau 200 ms + thời gian bật AVAudioEngine: tiếng nói ngay lúc vừa bấm có thể bị mất đầu; nên đợi chữ “Đang nghe”.
- ⌘V dùng mã phím ảo 9 (vị trí phím V trên ANSI); bố cục bàn phím khác (Dvorak…) có thể không ra ⌘V.
- Khôi phục clipboard sau 350 ms: ứng dụng đích quá chậm đọc clipboard có thể dán nhầm nội dung cũ. Ứng dụng đích nhận được chữ qua clipboard nên có thể lưu lịch sử dán của riêng nó.
- Chuyển ứng dụng trong lúc “Đang dịch” ⇒ nếu người dùng chuyển sang MỘT ỨNG DỤNG KHÁC, chữ dán vào ứng dụng đang focus lúc có kết quả (bundle id gửi engine là ứng dụng lúc bắt đầu ghi); nếu chính vflow đang ở phía trước thì vflow đưa app đích lên trước rồi mới dán (`PasteTargetPolicy`).
- **Command Mode**: `kAXSelectedTextAttribute` không phải app nào cũng hỗ trợ (đa số terminal, một số editor tuỳ biến) ⇒ tự rơi về ⌘C tổng hợp, mất thêm tới ~250 ms; app hoàn toàn không hỗ trợ cả hai (không đáp ứng ⌘C) ⇒ coi là không có đoạn chọn (`draft`, soạn mới) thay vì lỗi. ⌘C dùng mã phím ảo 8 (vị trí phím C trên ANSI) — bố cục khác ANSI có thể không ra ⌘C đúng.
- **Đúp ⌥ (ghi khoá)**: nếu bấm ⌥ quá chậm giữa hai lần chạm (> 350 ms) thì KHÔNG tính là đúp — mỗi lần chạm coi như độc lập (bị bỏ qua); phải chạm lại từ đầu.

## V2 — Thống kê, Cài đặt mở rộng, Xem chữ chạy trực tiếp, Gợi ý từ điển

Đợt này phủ các tính năng engine mới thêm ở `contract/engine-api.md` (thống kê, xuất/nhập, chẩn
đoán, `app_rules`, dấu câu bằng giọng/nói nhỏ/giọng điệu, gợi ý từ điển, xem chữ trực tiếp,
`post.degraded`). `VFlowCore/EngineAPIv2.swift` + `LivePreview.swift` + `StatsPresentation.swift`
giữ TOÀN BỘ kiểu/logic thuần mới (có test); lớp AppKit chỉ hiển thị.

**Tab "Thống kê"** (`StatsView.swift`, thứ 2 trong thanh bên, ⌘2): lời chào lớn theo tổng số từ
toàn thời gian (`VFlowCore.StatsGreeting`, 5 ngưỡng: 0/1–99/100–999/1.000–9.999/≥10.000); 4 thẻ
(Từ đã nói, WPM trung bình — "—" kèm gợi ý khi chưa đủ 60 giây audio chứ KHÔNG BAO GIỜ số 0 giả,
Chuỗi ngày, Chuỗi dài nhất); lưới "Hoạt động N tuần" 7×N (tuần bắt đầu Thứ Hai, cột phải nhất là
tuần hiện tại, 5 mức cường độ theo phân vị — `VFlowCore.ActivityHeatmap`/`ActivityIntensity`, có
test biên tháng/năm/tuần đầu thiếu ngày/ngày tương lai/mọi ngày bằng nhau); "Từ của bạn đi đâu" —
top 10 ứng dụng, biểu tượng thật qua `NSWorkspace` (`StatsAppIdentity`, bundle id `"unknown"`/không
tìm thấy ⇒ biểu tượng chung + "Không rõ"). Trạng thái rỗng (`ContentUnavailableView`), tắt
(`stats_enabled=false` ⇒ thẻ "Thống kê đang tắt" + nút Bật/Mở Cài đặt), và lỗi engine thật (Thử
lại) — không bao giờ số giả. Làm mới khi mở tab, khi app lấy lại focus
(`NSApplication.didBecomeActiveNotification`), và sau mỗi dictation thành công (thông báo
`Notification.Name.vflowStatsMayHaveChanged`, `AppController` tự phát sau khi chèn chữ — MỘT nguồn
sự kiện chung, không poll). Thẻ "Hôm nay" ở Tổng quan bấm vào mở thẳng tab này.

**Cài đặt mở rộng** (`SettingsViewV2.swift`; từ Q1 cửa sổ chỉ còn 5 mục `SettingsCategory` = `VFlowCore.SettingsPane`, xem mục Cài đặt bên trên):
- **Giọng nói**: dấu câu bằng giọng (`voice_punctuation`, kèm ví dụ "xuống dòng"/"dấu phẩy" và lưu ý
  không nhầm lời nói thường), nói nhỏ (`whisper_mode`), xem chữ chạy trực tiếp (`live_preview`), tự
  dừng khi im lặng (dời từ "Chung" — vẫn `silence_stop_seconds`), giọng điệu (`tone`: chỉ áp dụng
  Gọn/Thư, vô hiệu hoá kèm lý do khi `cloud_llm` tắt).
- **Ứng dụng**: trình sửa `app_rules` — hàng icon+tên+bundle id nhỏ+Picker chế độ; thêm bằng
  `NSOpenPanel` (chọn `.app`, đọc `Bundle(url:).bundleIdentifier`) hoặc từ danh sách ứng dụng đang
  chạy (`NSWorkspace.runningApplications`); chế độ Gọn/Thư gắn nhãn "gửi chữ qua 9Router" + cảnh báo
  khi `cloud_llm` tắt (rơi về Làm sạch); kiểm hợp lệ bundle id phía client TRƯỚC khi gửi
  (`VFlowCore.AppRuleValidation`, cùng regex với `engine/post/settings.js`).
- **Dữ liệu & Riêng tư** (gộp "Lịch sử & riêng tư" cũ): lịch sử (công tắc + xoá), riêng tư, công tắc thống kê + "Xoá thống kê…" (xác nhận, `DELETE /v1/stats`), học từ lần sửa
  (`learn_from_edits`), Xuất dữ liệu… (`NSSavePanel`, tệp quyền 0600, công tắc gồm lịch sử — mặc
  định tắt), Nhập dữ liệu…/Nhập và THAY THẾ (`NSOpenPanel`, hiện `applied`/lỗi cụ thể — engine từ
  chối CẢ GÓI nếu một phần sai, không nhập nửa vời), Sao chép chẩn đoán (clipboard) / Lưu chẩn
  đoán… (`GET /v1/diagnostics`, không bao giờ chứa khoá/token).

**Xem chữ chạy trực tiếp**: khi `live_preview` bật, model trong máy đã tải, và đang ghi dictation
(không phải Command Mode), `AppController` gửi `POST /v1/partial` (PCM đã ghi TỚI LÚC ĐÓ, qua
`AudioRecorder.snapshotPCM()` — không dừng ghi) mỗi ~1 giây qua
`VFlowCore.LivePreviewCoordinator`/`LivePreviewTick` (TỐI ĐA một yêu cầu đang bay, bỏ qua lượt khi
bận/429 `busy`, tạm dừng cho lượt ghi hiện tại sau 3 lỗi liên tiếp, huỷ khi dừng/huỷ ghi — có test
dùng engine giả, gồm một kiểm tra concurrency thật bằng `Task` chồng lấn). HUD (`OverlayPanel.swift`)
hiện thêm một dòng chữ mờ tối đa 2 dòng, CHỈ PHẦN CUỐI (`.lineLimit(2).truncationMode(.head)` +
`VFlowCore.LivePreviewDisplay.capToTail` chặn chuỗi quá dài) — KHÔNG BAO GIỜ chèn vào ô đích, kết
quả cuối vẫn là bản dịch đầy đủ của `/v1/transcribe` sau khi nhả phím.

**Gợi ý từ điển** (`DictionaryView.swift`): mục "Gợi ý từ lần anh sửa" phía trên danh sách (chỉ hiện
khi có — `GET /v1/dictionary/suggestions`), mỗi gợi ý có từ đúng/cách nói sai/số lần gặp, nút "Thêm
vào từ điển" (mở sheet Thêm mục có sẵn dữ liệu, không tự lưu thẳng) và "Bỏ qua"
(`POST .../dismiss`); cập nhật danh sách ngay sau khi thêm/bỏ qua.

**Kết quả suy giảm** (`post.degraded`/`degraded_reason`): HUD hiện thông điệp ngắn đúng nguyên nhân
(`VFlowCore.DegradedText` — `llm_timeout`→"9Router chậm…", `llm_error`→"9Router lỗi…",
`guard`→"Bản viết lại bị chặn vì đổi nghĩa…", `cloud_disabled`→"Đám mây đang tắt…"), chữ đã chèn
KHÔNG đổi; ghi vào lịch sử qua `HistoryEntry.degradedReason` (trường mới, tuỳ chọn).

**Engine (phạm vi hẹp đã duyệt riêng)**: `GET /healthz` nay có `max_audio_seconds`; mặc định
`live_preview` đổi `false`→`true` (đo thật p95 `/v1/partial` ở 10 s audio = 111 ms, dưới ngưỡng
500 ms); `GET /v1/stats` nay có `week_start:"monday"` (contract đã khai từ đầu nhưng
`engine/post/stats.js` không trả — vá đúng, có test; xem `contract/engine-api.md`).

## V3 — Nhóm A: dạy từ, lưu âm thanh để nghe lại, HUD, giao diện, "Hôm nay", ký hiệu theo ngữ cảnh, đo độ trễ

| Tính năng | Ở đâu | Ghi chú ngắn |
|---|---|---|
| **Dạy từ bằng giọng** | tab Từ điển › "Dạy từ bằng giọng…" | Nhập từ đúng, nói 3–5 lần (mỗi lần ≤ 10 s ở client; engine nhận tối đa 15 s), mỗi lần `POST /v1/teach` trả CHỮ THÔ máy nghe được ("Nghe ra: …", chưa qua từ điển/làm sạch); gom các cách nghe khác nhau rồi lưu vào từ điển (gộp, không trùng). Không ghi lịch sử, thống kê hay âm thanh. |
| **Lưu âm thanh để nghe lại** (tuỳ chọn) | Cài đặt › Dữ liệu & Riêng tư; nút nghe lại ở tab Lịch sử | **Tắt mặc định.** Xem nguyên tắc riêng tư ngay dưới. |
| **Vị trí và cỡ thanh ghi âm (HUD)** | Cài đặt › Chung › "Thanh ghi âm" | Vị trí "Dưới màn hình" (mặc định, như cũ) hoặc "Cạnh notch"; cỡ Gọn/Vừa/Lớn = 0/2/4 dòng chữ chạy trực tiếp. Có hiệu lực từ lần ghi kế tiếp. |
| **Giao diện Sáng/Tối** | Cài đặt › Chung › "Giao diện" (và nút ở thanh công cụ) | Hệ thống/Sáng/Tối, áp ngay cho mọi cửa sổ vflow, nhớ qua lần mở sau. |
| **Viên "Hôm nay"** | thanh công cụ cửa sổ chính | "Hôm nay: N từ", bấm mở tab Thống kê; ẩn khi chưa có số thật (không hiện 0 giả). |
| **Ký hiệu theo ngữ cảnh** | engine (`context_symbols`, mặc định bật) | "gạch chéo"→`/`, "a còng"→`@`, "hai chấm hai gạch chéo"→`://`… CHỈ trong terminal/IDE/công cụ AI/chat nhóm (danh sách bundle id cứng, so khớp chính xác, `engine/post/contextsymbols.js`); ứng dụng thường (Notes, Mail…) giữ chữ. |
| **Độ trễ bắt đầu ghi** | Cài đặt › Nâng cao › "Độ trễ bắt đầu ghi" | Từ lúc nhấn phím tới khối âm thanh đầu; 50 lượt gần nhất, CHỈ trong RAM (không ghi đĩa, không chứa giọng nói); chưa có lượt nào ⇒ "Chưa có lượt ghi nào" (không bịa 0 ms). |

Engine còn giữ cài đặt `vocab_boost` (hotwords; đo thật trên model Zipformer-vi hiện dùng không đổi đầu ra câu nào mà chậm thêm ~28–35%) nhưng từ Q1 client KHÔNG còn công tắc nào cho nó: không đọc, không gửi `vocab_boost` (khoá lạ trong phản hồi `/v1/settings` bị bỏ qua, có test `SettingsUnknownKeyTests`).

### Nguyên tắc riêng tư về âm thanh (lưu để nghe lại)
- **Tắt mặc định.** Khi tắt: không có tệp nào được tạo, phản hồi dictation không có `audio_id`. Bật cần xác nhận (hộp thoại nêu nơi lưu/giới hạn) và chỉ có nghĩa khi "Lưu lịch sử" đang bật — tắt Lịch sử ⇒ lưu âm thanh tự tắt theo (bật lại Lịch sử KHÔNG tự bật lại âm thanh).
- **Nơi lưu:** CHỈ trên máy này, `$VFLOW_HOME/audio/<id>.wav` (mặc định `~/.vflow/audio/`; WAV 16 kHz mono 16-bit) cùng `index.json` (id, thời điểm, độ dài, app, chế độ — **không có chữ của câu nói**). Không gửi đi đâu.
- **Quyền:** thư mục `0700`, mỗi tệp `0600` (engine ép lại `0700` mỗi lần ghi nếu thư mục cũ rộng hơn).
- **Ngân sách:** `audio_history_mb` 50–2000 (mặc định 200) và `audio_history_days` 1–90 (mặc định 7); vượt thì xoá bản **cũ nhất** trước, quá hạn thì xoá; quét cả lúc engine khởi động. Giá trị ngoài miền bị engine từ chối (`400 bad_request`).
- **Xoá:** từng câu (`DELETE /v1/audio/<id>`, nút "Xoá âm thanh của câu này"), hoặc tất cả (`DELETE /v1/audio`, "Xoá toàn bộ âm thanh…"). Id lạ/ký tự lạ/`..` ⇒ `404`, không đọc/xoá được tệp ngoài thư mục audio.
- **Không nằm trong export và chẩn đoán:** `GET /v1/export` (kể cả `include_history=1`), `GET /v1/diagnostics`, `/v1/settings`, `/healthz`, thông báo lỗi và log của engine không chứa byte âm thanh, token, khoá 9Router hay đường dẫn tuyệt đối thư mục cá nhân (probe kiểm bằng chuỗi mồi). Chỉ có DUY NHẤT một đường đưa âm thanh ra ngoài: người dùng chủ động bấm "Xuất ZIP…" (`GET /v1/audio/export`, ZIP kiểu "store": các `.wav` + `index.json`).
- Mọi endpoint âm thanh/`/v1/teach` cần token như các endpoint khác (thiếu/sai ⇒ `401`), chỉ nhận `Host` 127.0.0.1/localhost, không có CORS.

### Bộ kiểm độc lập phía engine: `client/scripts/probe-group-a.mjs`
```sh
node client/scripts/probe-group-a.mjs   # ~5 giây; thoát 0 nếu mọi khẳng định PASS, 1 nếu có FAIL, 2 nếu không dựng được môi trường
```
- Tự dựng `VFLOW_HOME` + `HOME` giả trong thư mục tạm, chạy `node bin/vflow.js serve` ở cổng NGẪU NHIÊN 27800–27899 (không bao giờ 7611, không đụng `~/.vflow` thật) và một máy chủ STT từ xa GIẢ theo `contract/remote-stt.md` (trả chữ do script đặt — không cần model, không tốn RAM). Tự tắt engine và xoá thư mục tạm kể cả khi lỗi.
- In bảng PASS/FAIL tiếng Việt, mỗi dòng kèm giá trị quan sát được: xác thực (401/403), `/v1/teach` (định dạng sai, > 15 s ⇒ 413, đồng thời ⇒ 429, không tác dụng phụ lên history/thống kê/từ điển/âm thanh), lưu âm thanh tắt/bật (không tệp/`audio_id`, quyền 0600/0700, `/v1/audio` khớp đĩa), ngân sách + hạn ngày (đuổi bản cũ nhất, dọn quá hạn/mồ côi lúc khởi động), xoá + path traversal, ZIP (tự đọc cấu trúc, CRC32 từng tệp, `index.json` không có chữ), rò rỉ (export/chẩn đoán/log), ký hiệu theo ngữ cảnh, miền giá trị cài đặt. Dòng "(thông tin)" là quan sát không tính PASS/FAIL.
- `VFLOW_PROBE_ENGINE_BIN=<đường dẫn bin/vflow.js của một BẢN SAO engine>` cho phép thử phá có chủ đích (đột biến) để xác nhận probe thật sự bắt lỗi.
- Giới hạn: chỉ kiểm engine qua HTTP (không kiểm giao diện Swift — xem `MANUAL-TEST.md` mục L); STT là bản giả nên không đo chất lượng nhận dạng; kiểm "quá hạn" dựng index/tệp giả trực tiếp (engine tính tuổi theo trường `at` trong `index.json`, không theo mtime của tệp).

### Quan sát đã biết của engine (từ probe; không phải lỗi giao diện)
- Kho âm thanh coi mọi `.wav` KHÔNG có trong `index.json` là "mồ côi" và xoá lúc khởi động — kể cả khi `index.json` bị hỏng/mất (khi đó cả kho bị xoá). Ghi `index.json` là nguyên tử nên hiếm xảy ra.
- Ở chế độ Thường, câu kết thúc bằng "a còng <tên>" (vd. "…cho an a còng example") ra `an@example` kèm MỘT dấu cách cuối (dành cho mention gõ tiếp); chế độ Lập trình (terminal ở Tự động) không thừa dấu cách.
