# vflow — client macOS

Giữ **⌥ Option trái**, nói, nhả phím ⇒ chữ được dán vào ô đang gõ ở mọi ứng dụng (kể cả Terminal). **Đúp ⌥ trái** (hai lần chạm nhanh) ⇒ ghi "khoá" (hands-free, không cần giữ phím) — bấm ⌥ một lần nữa để xong. **Esc** huỷ ngay lập tức ở bất kỳ kiểu ghi nào. Giữ **⌥ trái + ⌃ trái** (⌃ trong 400 ms đầu) ⇒ Command Mode (sửa/soạn văn bản bằng lời, xem mục riêng bên dưới). Client chỉ nói chuyện với engine cục bộ `http://127.0.0.1:7611` theo `contract/engine-api.md`; không mạng ngoài, không analytics, không tự cập nhật, không thư viện bên thứ ba.

Từ M4a, vflow là **app thường**: biểu tượng Dock, ⌘-Tab, menu ứng dụng đầy đủ, và cửa sổ chính **"vflow"** với 4 mục xếp theo 2 nhóm ở thanh bên — **Sử dụng** (Tổng quan, Lịch sử), **Cá nhân hoá** (Từ điển, Snippets); **Cài đặt** (từ U1) là **cửa sổ RIÊNG chuẩn macOS** (⌘,; menu "vflow › Cài đặt…"), không còn là một mục trong thanh bên. Biểu tượng thanh menu vẫn còn nhưng chỉ là phụ (có công tắc ẩn/hiện ở Cài đặt › Chung, mặc định bật) — từ U1, biểu tượng này là ảnh **TEMPLATE đơn sắc** (`isTemplate = true`): macOS tự vẽ **trắng** trên thanh menu tối, **đen** trên thanh menu sáng; trạng thái (nghe/dịch/lỗi/thiếu quyền) phân biệt bằng **hình** huy hiệu góc dưới-phải (chấm đặc/vòng/sao lấp lánh/tam giác cảnh báo — xem mục Logo), không dựa vào màu. **Đóng cửa sổ chính (nút đỏ) KHÔNG thoát app** — ghi âm bằng phím nóng và engine vẫn hoạt động; thoát hẳn bằng **⌘Q** hoặc menu "vflow › Thoát vflow". Lần đầu mở (hoặc khi chưa đủ 3 quyền macOS), một tờ **Chào mừng** tự hiện hướng dẫn cấp quyền từng bước (dấu tích tự cập nhật); mở lại được bất cứ lúc nào từ menu "Trợ giúp › Xem hướng dẫn chào mừng…".

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
- `--open-tab tongquan|lichsu|tudien|snippet|caidat`: mở cửa sổ chính thẳng vào mục đó; riêng `caidat` mở CỬA SỔ CÀI ĐẶT (không còn là mục trong thanh bên) — dùng để chụp ảnh.
- `--open-settings-tab general|cloud|historyPrivacy|advanced`: mở cửa sổ Cài đặt thẳng vào mục đó (chụp ảnh).
- `--appearance light|dark`: ép giao diện sáng/tối (chỉ để chụp ảnh nhất quán, không đổi cài đặt hệ thống).
- `--no-welcome`: không tự hiện tờ Chào mừng lần đầu dù chưa đủ quyền/chưa từng xem (dùng khi chụp ảnh các cửa sổ khác để tờ Chào mừng không che mất).
- `--demo-icon [--demo-seconds N]`: cửa sổ RIÊNG hiện biểu tượng thanh menu (template) trên nền tối/sáng ở cả 5 trạng thái huy hiệu, không chạy engine/phím nóng — dùng để chụp ảnh chứng minh trắng/đen tự động mà không chụp thanh menu thật.
- `--render-offscreen <mục> --out <path.png> [--render-wait-ms N]`: chụp một mục ra PNG mà KHÔNG BAO GIỜ hiện cửa sổ lên màn hình — xem mục "Công cụ chụp ảnh ngoài màn hình" bên dưới (U3).

Biến môi trường `VFLOW_HOME` (mặc định `~/.vflow`, giống engine) đổi nơi client đọc `client.json`/`token` và lưu `history.jsonl` — dùng để thử nghiệm mà không đụng dữ liệu thật, ví dụ: `VFLOW_HOME=/tmp/vflow-test VFlow.app/Contents/MacOS/VFlow`. **Từ U2**: khi có `VFLOW_HOME`, các công tắc UI (chế độ, Lưu lịch sử, Hiện cửa sổ khi mở app, Hiện biểu tượng thanh menu, đã xem Chào mừng…, vị trí/kích thước cửa sổ) cũng được CÔ LẬP — dùng một `UserDefaults(suiteName:)` suy ra từ `VFLOW_HOME` bằng băm ổn định FNV-1a (`VFlowCore.VFlowDefaults`, một lớp truy cập duy nhất thay mọi chỗ gọi `UserDefaults.standard`/`setFrameAutosaveName` trực tiếp — xem `VFlow.WindowFramePersistence`), nên hai `VFLOW_HOME` khác nhau và bản `/Applications/vflow.app` thật KHÔNG còn thấy khoá của nhau. KHÔNG có `VFLOW_HOME` ⇒ `.standard` như cũ (không di cư dữ liệu, app thật không đổi hành vi).

Hai biến môi trường CHỈ dùng để chụp ảnh tự động (không có tác dụng gì khi không đặt, không bao giờ dùng khi chạy thật):
- `VFLOW_DEMO_PERMISSIONS=granted|missing`: giả lập quyền macOS đủ/thiếu mà không đụng TCC thật.
- `VFLOW_PRINT_WINDOW_RECT=1`: ghim cửa sổ chính/Cài đặt/Chào mừng vào vị trí cố định và in toạ độ ra stdout (`VFLOW_WINDOW_RECT <nhãn> x y w h`, hệ quy chiếu `screencapture -R`) để chụp đúng khung cửa sổ, không cần quyền Ghi màn hình cho `CGWindowListCopyWindowInfo`.

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

`<mục>`: `tongquan`, `lichsu`, `tudien`, `tudien:them-loi` (sheet Thêm mục với lỗi hợp lệ sẵn — GIỚI
HẠN: ảnh chỉ có cửa sổ chính, sheet không hiện trong ảnh — xem ghi chú ở
`StatusWindowController.captureDictionaryAddInvalidOffscreen`), `snippet`,
`caidat[:general|cloud|historyPrivacy|advanced]`, `welcome`. HUD (thanh trạng thái 5 trạng thái) dùng
`--demo-overlay <ghi|khoa|dich|xong|loi> --render-offscreen --out <path>` (không cần `<mục>`).

### `client/scripts/snapshot.sh <thư mục đầu ra>`
Công cụ LÂU DÀI chụp TOÀN BỘ màn hình (sáng + tối): dựng VFlow, tạo hai `VFLOW_HOME` cô lập tạm thời
(`full`: dữ liệu mẫu — lịch sử nhiều ngày, từ điển, snippets, engine THẬT chạy cục bộ chỉ phục vụ
`/healthz`+`/v1/dictionary`+`/v1/snippets`, không cần model STT tải sẵn; `empty`: trống, quyền giả lập
thiếu), gọi `--render-offscreen` cho từng cặp (mục, sáng/tối), rồi dọn sạch — không đụng `~/.vflow`
thật, không để lại tiến trình/thư mục tạm. Dữ liệu mẫu trong `snapshot-seed.mjs` không chứa tên
riêng/khoá thật.

```sh
client/scripts/snapshot.sh /tmp/vflow-snapshots   # ⇒ ~34 ảnh PNG, xem /tmp/vflow-snapshots/snapshot.log
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
| `VFlowCore` (thư viện, test được) | `Hotkey.swift` máy trạng thái phím (giữ/đúp-khoá/Command Mode/Esc) + phân loại CGEvent; `Audio.swift` bộ chuyển 16 kHz mono Int16 theo khối (sinc cửa sổ Blackman, chống răng cưa), downmix, LE, mức âm, bộ đệm “thử lại”; `Clipboard.swift` chèn bằng clipboard + khôi phục; `SelectionCapture.swift` lấy đoạn đang chọn (AX/⌘C tổng hợp, có kiểm soát) cho Command Mode; `TextMatch.swift` (`VietnameseMatch`) gấp dấu/chuẩn hoá khớp luật engine (`fold`/`normalizeMatch`); `EngineAPI.swift` yêu cầu/phản hồi/ánh xạ lỗi tiếng Việt (transcribe, healthz, dictionary, corrections, snippets, settings, command); `EngineSupervisor.swift` giám sát engine con; `ClientConfig.swift`; `VFlowHome.swift` tôn trọng `VFLOW_HOME`; `History.swift` (`HistoryStore`, `HistoryEntry`, `HistoryGate`) lưu lịch sử chỉ-văn-bản vào `history.jsonl`; `Dictionary.swift`/`DictionaryOrchestration.swift` và `Snippet.swift`/(`SnippetOrchestration` trong cùng tệp) kiểm hợp lệ + mẫu đọc-sửa-ghi chung cho `/v1/dictionary` và `/v1/snippets`; `Settings.swift` (`AppSettings`, `SettingsPatch`, `SettingsValidation`, `EnterAction`) cho `/v1/settings` và quyết định gửi phím Enter; `Dictation.swift`, `Overlay.swift` (gồm trạng thái ghi khoá/Command Mode) quyết định hiển thị; `StatusModel.swift` mô hình thuần dùng CHUNG cho menu và tab Tổng quan (`StatusModel`, `PermissionKind`/`PermissionItem`, `ConflictDetector`/`ConflictText` dò ứng dụng đọc chính tả khác qua `RunningAppsProvider`, `ShowWindowPreference`); `DesignSystem.swift` (U1, hệ thống thiết kế thuần) — `BrandColor`/`ContrastText` (màu nhấn cam #ED6300 + kiểm tương phản WCAG AA), `ModeCloudLabel` (nhãn "Trong máy"/"Gửi chữ qua 9Router" lấy từ `DictationMode.sendsTextToCloud`), `ModelReasonText` (mã lý do model → chữ thân thiện), `PermissionsProgress` ("n/3"), `WelcomeDecision` (có tự hiện Chào mừng hay không), `HeroStatus`/`HeroStatusDecision` (trạng thái thẻ lớn Tổng quan), `TodaySummary`/`TodayStats` (tổng hợp "Hôm nay" từ lịch sử); `VFlowDefaults.swift` (U2, lớp truy cập UserDefaults duy nhất, cô lập theo `VFLOW_HOME`); `HistoryGrouping.swift` (U2, gom lịch sử theo ngày); `ListSorting.swift` (U2, sắp xếp A–Z/dùng nhiều dùng chung Từ điển/Snippets); `DictionaryFormValidation`/`SnippetFormValidation` (U2, trong `Dictionary.swift`/`Snippet.swift`, kiểm hợp lệ ngay khi gõ); `WaveformMeter` (U2, trong `Overlay.swift`, chiều cao vạch sóng âm theo mức). |
| `VFlow` (AppKit/SwiftUI mỏng) | event tap, AVAudioEngine, NSPasteboard + ⌘V/Return/⌘C tổng hợp (`TextInserter.swift`: `PasteKeystroke`/`ReturnKeystroke`/`CopyKeystroke`/`AXSelection`), NSPanel thanh trạng thái, `main.swift` (menu ứng dụng, `--open-tab`, `--open-settings-tab`, `--appearance`, `--no-welcome`, `--demo-icon`), `StatusWindow.swift` cửa sổ chính "vflow" (`MainWindowView`, sidebar 4 mục xếp 2 nhóm + ⌘1…⌘4), `SettingsWindow.swift` cửa sổ Cài đặt RIÊNG (`SettingsRootView`, 4 mục `SettingsCategory`, ⌘,), `WelcomeWindow.swift` tờ Chào mừng lần đầu (`WelcomeView`, cờ `hasSeenWelcome`), `Theme.swift` màu nhấn thương hiệu + `cardBackground()` dùng chung, `OverviewView.swift` (bảng điều khiển, U1) /`HistoryView.swift`/`DictionaryView.swift`/`SnippetsView.swift`/`SettingsView.swift` (gồm `ModeSection`, `CloudSettingsSection`, `GeneralSettingsTab`, `HistoryPrivacySettingsTab`, `AdvancedSettingsTab`) nội dung từng mục, `MainTab.swift`, NSStatusItem + menu (`StatusMenu.swift`, có `setVisible`, dùng `BrandIcon` cho biểu tượng template + huy hiệu trạng thái), `BrandIcon.swift` nạp logo-mark màu (header) và logo-mark template (thanh menu) từ bundle, `WindowRectDebug.swift` (chỉ kiểm tự động), `Permissions.swift` (quyền thật, nối `PermissionKind`, có cờ môi trường `VFLOW_DEMO_PERMISSIONS` chỉ-để-chụp-ảnh), `ConflictProvider.swift` (`NSWorkspace` thật), SMAppService, `WindowFramePersistence.swift` (U2, tự lưu/đọc vị trí cửa sổ qua `VFlowDefaults` khi có `VFLOW_HOME`, dùng `setFrameAutosaveName` chuẩn AppKit khi không có). |
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
- Ghi tối đa 120 s rồi tự gửi (cảnh báo ở giây thứ 100). Đang dịch thì không nhận lần ghi mới (không chồng). Mất sự kiện nhả phím ⇒ phát hiện qua trạng thái phím thật mỗi 50 ms (chỉ áp dụng kiểu "giữ phím" — ghi khoá không phụ thuộc trạng thái giữ ⌥); tap bị hệ thống tắt ⇒ bật lại và huỷ lần ghi; đang dịch quá 200 s ⇒ bỏ yêu cầu, về rảnh.

### Command Mode (⌥ trái + ⌃ trái)
Giữ ⌥ trái; nếu ⌃ trái được bấm trong **400 ms đầu** của lần giữ đó (dù đã qua ngưỡng 200 ms và bắt đầu ghi thường hay chưa) ⇒ chuyển sang Command Mode: thanh trạng thái "Đang nghe lệnh". ⌃ đến sau 400 ms hoặc phím khác ⇒ huỷ như tổ hợp phím thường (không vào Command Mode). Nhả ⌃ sớm không kết thúc Command Mode (chỉ là phím khởi động); chỉ nhả ⌥ (hoặc Esc) mới dừng/huỷ, giống kiểu "giữ phím" thường.

Luồng: (a) **lúc bắt đầu**, lấy đoạn đang chọn — thử Accessibility (`kAXSelectedTextAttribute` của phần tử focus) trước; không có (terminal, app tuỳ biến) thì thử sao chép tổng hợp ⌘C có kiểm soát: lưu nguyên clipboard, gửi ⌘C, chờ tối đa 250 ms thấy `changeCount` đổi thì đọc chuỗi rồi khôi phục clipboard; không đổi ⇒ không có đoạn chọn (xem `VFlowCore.SelectionCapture`, chạy song song với bước (b) để không mất đầu câu lệnh); (b) ghi âm lệnh, nhả ⇒ `POST /v1/transcribe?mode=normal` lấy chữ lệnh; (c) `POST /v1/command {instruction, selection, app}`; (d) thành công ⇒ dán kết quả bằng đúng đường dán ⌘V hiện có (đoạn chọn vẫn đang bôi đen nên sẽ bị thay thế), thanh trạng thái "Xong"; (e) lỗi (`cloud_disabled`, `rewrite_unavailable`, `timeout`, `bad_request`, lỗi engine khác) ⇒ hiện lỗi tiếng Việt rõ, **không dán gì, không sửa clipboard**. Lịch sử chỉ lưu **lệnh và kết quả** (`mode: "command:edit"` hoặc `"command:draft"`) — tuyệt đối không lưu đoạn đã chọn.

## Âm thanh và chèn chữ
- AVAudioEngine (tạo mới mỗi lần ghi, theo kịp đổi thiết bị) ⇒ downmix ⇒ 16 kHz Int16 LE trong RAM ⇒ `POST /v1/transcribe?mode=<chế độ>&app=<bundle id ứng dụng đang focus>` với `Content-Type: audio/L16; rate=16000; channels=1`. Không gửi `model` (engine chọn). **Không ghi âm thanh xuống đĩa**, không log văn bản.
- “Thử lại lần cuối”: giữ tối đa MỘT bản âm thanh trong RAM, tự xoá sau 5 phút hoặc khi có kết quả (kể cả “không nghe thấy gì”).
- Chèn: ghi `text` lên clipboard (kèm `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`), gửi ⌘V tổng hợp, chờ 350 ms, rồi khôi phục **nguyên** clipboard cũ (mọi mục, mọi kiểu) — trừ khi `changeCount` đổi (người dùng vừa sao chép thứ khác) thì không đè. Không có quyền gửi phím ⇒ chữ để lại trên clipboard và báo “bấm ⌘V”.
- `silence:true` hoặc chữ rỗng ⇒ không chèn, hiện “Không nghe thấy gì”. Chế độ `email` mà viết lại lỗi ⇒ vẫn dán bản chưa viết lại và báo lỗi kèm mã.

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

Biểu tượng thanh menu (`org.aios.vflow`) vẫn còn nhưng giờ chỉ là PHỤ — có công tắc "Hiện biểu tượng trên thanh menu" ở Cài đặt › Chung (mặc định bật); ảnh TEMPLATE đơn sắc, macOS tự vẽ trắng/đen theo nền thanh menu (xem mục Logo). Trên thanh menu chật (nhiều mục, hoặc notch của MacBook che bớt) macOS có thể tự ẩn biểu tượng mà không báo gì; cách điều khiển CHÍNH không phụ thuộc nó: cửa sổ **"vflow"**, mở được từ Dock, ⌘-Tab, hoặc menu ứng dụng bất cứ lúc nào.

**Đóng cửa sổ chính (nút đỏ) KHÔNG thoát app** — ghi âm bằng phím nóng vẫn hoạt động, engine con vẫn chạy; cửa sổ tự ghi chú điều này ở chân mỗi tab. Thoát hẳn bằng **⌘Q** hoặc menu "vflow › Thoát vflow" (cũng có ở Cài đặt › Chung). Nếu cửa sổ bị đóng và cần mở lại: bấm Dock, `open client/build/VFlow.app`, hoặc menu thanh trạng thái "Mở cửa sổ vflow".

## Cửa sổ chính "vflow"
Một cửa sổ (`.titled`, đổi cỡ được, mặc định ≈960×680, tối thiểu ≈800×560, nhớ kích thước/vị trí — cô lập theo `VFLOW_HOME` từ U2, xem `VFlow.WindowFramePersistence`), thanh công cụ thống nhất (tiêu đề mục đang chọn — MỘT nơi duy nhất, nội dung không lặp lại tiêu đề), thanh bên có logo+tên "vflow" ở đầu rồi 4 mục xếp 2 nhóm — **Sử dụng** (Tổng quan, Lịch sử), **Cá nhân hoá** (Từ điển, Snippets). **Từ U2**: mục đang chọn ở thanh bên KHÔNG dùng `List(selection:)` nữa (`NavigationSplitView`/`listStyle(.sidebar)` luôn tô màu nhấn HỆ THỐNG, không có API đổi) — tự vẽ (`VFlow.SidebarRow`, nút phẳng + viên thuốc cam thương hiệu khi chọn), vẫn điều khiển được bằng bàn phím (Tab/Space, ⌘1…⌘4)/VoiceOver, huy hiệu cam nhỏ ở "Tổng quan" khi có quyền macOS còn thiếu. Lần đầu mở, một thẻ nhỏ nhắc "Đóng cửa sổ không thoát vflow…" hiện một lần (đóng được, nhớ bằng `hasSeenCloseHint`) thay cho dòng chân trang cố định của U1. Phím tắt ⌘1…⌘4 chuyển mục (theo thứ tự trên); ⌘, mở cửa sổ Cài đặt (riêng, xem mục bên dưới). Màu nhấn cam thương hiệu #ED6300 (`Theme.accent`, `client/Sources/VFlow/Theme.swift`) dùng cho công tắc/mục chọn/nút chính; thẻ (`cardBackground()`) từ U2 dùng `controlBackgroundColor` đặc + viền `separatorColor` + bóng nhẹ (không còn `.regularMaterial` — không đủ phân biệt với nền cửa sổ ở giao diện TỐI, đã kiểm bằng ảnh chụp).

**Tổng quan** — bảng điều khiển (U1), lấy từ CÙNG MỘT mô hình thuần `StatusModel` (VFlowCore) với menu thanh trạng thái nên hai nơi không bao giờ nói khác nhau; nội dung và chữ hiển thị quyết định bởi các hàm thuần có test trong `VFlowCore/DesignSystem.swift` (`HeroStatusDecision`, `ModelReasonText`, `PermissionsProgress`, `TodayStats`, `ModeCloudLabel`):
- **Thẻ trạng thái lớn** đầu trang: "Sẵn sàng. Giữ ⌥ trái để nói", hoặc trạng thái vấn đề (thiếu quyền/đang khởi động engine/lỗi) kèm nút hành động phù hợp ("Cấp quyền…"/"Khởi động lại engine"/"Thử lại lần cuối"); từ U2 có biểu tượng + nền nhấn nhẹ THEO TRẠNG THÁI (cam thương hiệu khi sẵn sàng, cam cảnh báo khi thiếu quyền, đỏ khi lỗi); **cảnh báo xung đột phím** riêng nếu phát hiện ứng dụng đọc chính tả khác đang chạy (danh sách mặc định trong `VFlowCore.ConflictConfig`, đầu tiên là `com.sonpiaz.haynoi`/Haynoi); thẻ lỗi gần nhất có thể đóng.
- **Thẻ phím tắt** dạng keycap: Giữ ⌥ để nói · Bấm đúp ⌥ để khoá ghi âm · Esc để huỷ · Giữ ⌥+⌃ để ra lệnh (Command Mode) · nói "nhấn enter" cuối câu.
- **Thẻ chế độ**: 6 chế độ dạng LƯỚI 2 cột (từ U2, gọn hơn danh sách dọc của U1), icon + mô tả ngắn + nhãn "Trong máy"/"Gửi chữ qua 9Router" (`ModeCloudLabel`, lấy từ `DictationMode.sendsTextToCloud` — nguồn duy nhất, không viết lại tay), viền cam rõ khi đang chọn.
- **Thẻ quyền**: gọn "Đã cấp n/3" kèm dấu tích khi đủ; mở rộng từng dòng + nút "Cấp quyền…" khi thiếu.
- **Thẻ "Hôm nay"**: số câu, số từ, thời gian nói — tính THUẦN từ lịch sử trong ngày (`TodayStats.summarize`, có test); lịch sử tắt ⇒ "Lịch sử đang tắt" (không hiện số 0 giả).
- Mục **"Hệ thống"** thu gọn (`DisclosureGroup`): engine + danh sách model với chữ thân thiện thay mã kỹ thuật (`ModelReasonText.friendly`: `not_downloaded`→"Chưa tải về", `missing_token`→"Chưa có khoá truy cập", `tunnel_down`→"Chưa kết nối", `loading`→"Đang tải", `loaded`→"Sẵn sàng", mã lạ→"(mã đó)" — không bao giờ im lặng), "Thử lại lần cuối", "Khởi động lại engine", "Mở thư mục dữ liệu".

**Lịch sử** — các câu đã đọc chính tả, **gom theo ngày** từ U2 ("Hôm nay"/"Hôm qua"/ngày đầy đủ — `VFlowCore.HistoryGrouping`, hàm thuần có test cho biên nửa đêm), mới nhất trên cùng trong mỗi nhóm; mỗi dòng có biểu tượng ứng dụng đích THẬT (`NSWorkspace.icon(forFile:)` theo bundle id, dự phòng biểu tượng chung khi không rõ/app đã gỡ — xem `VFlow.AppIconResolver`), giờ, chip chế độ, văn bản. CHỈ lưu văn bản (`text_raw`, `text`, mode, app bundle id, model, audio_ms, timings) — **tuyệt đối không có âm thanh**; mục Command Mode lưu dạng `mode: "command:edit"|"command:draft"`, `text_raw` = lệnh đã nói, `text` = kết quả — **không bao giờ lưu đoạn đang chọn**. Lưu `<VFLOW_HOME>/history.jsonl` (JSONL, quyền 0600, ghi nối nguyên tử + tự dọn giữ tối đa 500 mục/30 ngày, dòng hỏng bị bỏ qua và đếm chứ không làm sập — xem `VFlowCore.HistoryStore`). Tìm kiếm ở thanh công cụ (`.searchable`), menu chuột phải (Sao chép, Sửa…, Thêm vào từ điển…, Xoá) + ⌘C cho mục đang chọn; "Sửa…" mở hộp sửa văn bản cuối, Lưu ⇒ `POST /v1/corrections` ⇒ hiện gợi ý `{term, spoken}`, CHỈ ghi vào từ điển khi người dùng bấm xác nhận từng gợi ý (không gợi ý thì nói rõ "Không có gợi ý", không tự dán lại văn bản đã sửa vào đâu cả); "Thêm vào từ điển…" (U2) mở sheet thêm nhanh, tiền điền cách nói bằng câu đã chọn. Xoá một mục, "Xoá toàn bộ lịch sử…" (xác nhận). Công tắc "Lưu lịch sử" ở Cài đặt › Lịch sử & riêng tư (mặc định bật; tắt ⇒ không ghi mục mới, không xoá mục cũ) — trạng thái rỗng phân biệt rõ "Chưa có câu nào" (gợi ý giữ ⌥) và "Lịch sử đang tắt" (`ContentUnavailableView`). Kết quả lỗi/im lặng không bao giờ vào lịch sử.

**Từ điển** — đọc `GET /v1/dictionary`, thêm/sửa/xoá qua `PUT /v1/dictionary` kiểu **đọc-sửa-ghi** (đọc lại ngay trước khi ghi, xem `VFlowCore.DictionaryOrchestration`, để không đè thay đổi của engine/cửa sổ khác giữa chừng). Thanh công cụ có nút "+", tìm kiếm (`.searchable`), sắp xếp A–Z/Dùng nhiều (`VFlowCore.ListSorting`, dùng chung với Snippets); mỗi dòng hiện "cách nói" dạng chip (`VFlow.SpokenChips`) + số lần dùng. Sheet thêm/sửa (từ U2) dùng `Form` grouped, kiểm hợp lệ NGAY KHI GÕ bằng CHÍNH luật engine (`VFlowCore.DictionaryFormValidation`, áp `DictionaryValidation.validate` lên danh sách SẼ CÓ sau khi lưu — không viết luật riêng, nên không lệch với contract: term trùng/quá dài/rỗng, spoken rỗng… đều có thông điệp tiếng Việt), nút Lưu vô hiệu khi còn lỗi. Trạng thái rỗng gợi ý ví dụ cụ thể ("Thêm 'deploy' với cách nói 'đi plôi'"). Engine không chạy ⇒ nói rõ bằng chữ đỏ, KHÔNG hiện danh sách rỗng giả.

**Snippets** — đọc `GET /v1/snippets`, thêm/sửa/xoá qua `PUT /v1/snippets` kiểu đọc-sửa-ghi giống Từ điển (xem `VFlowCore.SnippetOrchestration`). Mỗi mục: trigger, xem trước NHIỀU DÒNG nội dung (tối đa 2 dòng hiện, mở sheet để xem đủ), số lần dùng; cùng thanh công cụ "+"/tìm kiếm/sắp xếp và sheet `Form` kiểm hợp lệ ngay khi gõ (`VFlowCore.SnippetFormValidation`, áp `SnippetValidation.validate`) như Từ điển. Trạng thái rỗng gợi ý ví dụ ("link lịch hẹn → https://…"). Dòng hướng dẫn: nói đúng cả câu bằng trigger, hoặc "chèn \<trigger\>" trong câu.

## Cửa sổ Cài đặt (từ U1)
CỬA SỔ RIÊNG chuẩn macOS (`SettingsWindow.swift`), KHÔNG còn là mục trong thanh bên cửa sổ chính — mở bằng ⌘, hoặc menu "vflow › Cài đặt…"; `AppController.openSettingsWindow(tab:)` là một singleton, gọi lại chỉ đưa lên trước + đổi mục. Thanh công cụ dạng tab 4 mục (`SettingsCategory`):
- **Chung** — chế độ mặc định (`ModeSection`, cùng nguồn `DictationMode` với Tổng quan), Bật khi đăng nhập, Hiện cửa sổ "vflow" khi mở app, Hiện biểu tượng trên thanh menu, nút Thoát vflow.
- **Đám mây** (`CloudSettingsSection`, giữ nguyên hành vi M4a): công tắc "Cho phép gửi chữ qua 9Router" (`cloud_llm`), ô "Model" (`llm_model`, trống = chưa đặt, kèm cảnh báo Gọn/Thư/Command Mode sẽ không chạy), "Thời gian chờ" (`llm_timeout_ms`, 1–30 s), công tắc "Nhấn Enter bằng giọng" (`actions_enabled`) — đọc/ghi qua `GET/PUT /v1/settings`, hiệu lực ngay, lỗi `bad_request` hiện tiếng Việt, "Đang chờ engine khởi động…" khi chưa sẵn sàng.
- **Lịch sử & riêng tư** — công tắc "Lưu lịch sử" + "Xoá toàn bộ lịch sử…", câu giải thích riêng tư (âm thanh không rời máy; Gọn/Thư/Command Mode gửi CHỮ qua 9Router).
- **Nâng cao** — đường dẫn dữ liệu hiện dùng (tôn trọng `VFLOW_HOME`) + "Mở thư mục dữ liệu", phiên bản vflow.

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
- Chuyển ứng dụng trong lúc “Đang dịch” ⇒ chữ dán vào ứng dụng đang focus lúc có kết quả (bundle id gửi engine là ứng dụng lúc bắt đầu ghi).
- **Command Mode**: `kAXSelectedTextAttribute` không phải app nào cũng hỗ trợ (đa số terminal, một số editor tuỳ biến) ⇒ tự rơi về ⌘C tổng hợp, mất thêm tới ~250 ms; app hoàn toàn không hỗ trợ cả hai (không đáp ứng ⌘C) ⇒ coi là không có đoạn chọn (`draft`, soạn mới) thay vì lỗi. ⌘C dùng mã phím ảo 8 (vị trí phím C trên ANSI) — bố cục khác ANSI có thể không ra ⌘C đúng.
- **Đúp ⌥ (ghi khoá)**: nếu bấm ⌥ quá chậm giữa hai lần chạm (> 350 ms) thì KHÔNG tính là đúp — mỗi lần chạm coi như độc lập (bị bỏ qua); phải chạm lại từ đầu.
