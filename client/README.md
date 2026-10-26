# vflow — client macOS

Giữ **⌥ Option trái**, nói, nhả phím ⇒ chữ được dán vào ô đang gõ ở mọi ứng dụng (kể cả Terminal). **Đúp ⌥ trái** (hai lần chạm nhanh) ⇒ ghi "khoá" (hands-free, không cần giữ phím) — bấm ⌥ một lần nữa để xong. **Esc** huỷ ngay lập tức ở bất kỳ kiểu ghi nào. Giữ **⌥ trái + ⌃ trái** (⌃ trong 400 ms đầu) ⇒ Command Mode (sửa/soạn văn bản bằng lời, xem mục riêng bên dưới). Client chỉ nói chuyện với engine cục bộ `http://127.0.0.1:7611` theo `contract/engine-api.md`; không mạng ngoài, không analytics, không tự cập nhật, không thư viện bên thứ ba.

Từ M4a, vflow là **app thường**: biểu tượng Dock, ⌘-Tab, menu ứng dụng đầy đủ, và cửa sổ chính **"vflow"** với 5 mục — **Tổng quan**, **Lịch sử**, **Từ điển**, **Snippets**, **Cài đặt**. Biểu tượng thanh menu vẫn còn nhưng chỉ là phụ (có công tắc ẩn/hiện ở Cài đặt, mặc định bật). **Đóng cửa sổ chính (nút đỏ) KHÔNG thoát app** — ghi âm bằng phím nóng và engine vẫn hoạt động; thoát hẳn bằng **⌘Q** hoặc menu "vflow › Thoát vflow".

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
- `--demo-overlay ghi|dich|xong|loi [--demo-seconds N]`: chỉ hiện thanh trạng thái ở một trạng thái (để chụp ảnh), không chạy engine/phím nóng.
- `--no-prompt`: không bật hộp thoại xin quyền (dùng khi chạy thử tự động); vẫn kiểm và báo trạng thái quyền.
- `--open-tab tongquan|lichsu|tudien|snippet|caidat`: mở cửa sổ chính thẳng vào tab đó (dùng để chụp ảnh từng tab).

Biến môi trường `VFLOW_HOME` (mặc định `~/.vflow`, giống engine) đổi nơi client đọc `client.json`/`token` và lưu `history.jsonl` — dùng để thử nghiệm mà không đụng dữ liệu thật, ví dụ: `VFLOW_HOME=/tmp/vflow-test VFlow.app/Contents/MacOS/VFlow`.

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

**`install-app.sh`**: dựng bản đầy đủ, thoát nhẹ nhàng (AppleScript `quit`, chờ tối đa 10s, không `kill -9`) **chỉ** các tiến trình vflow có đường dẫn thực thi trong `client/build/VFlow.app` hoặc `/Applications/vflow.app`, sao chép bằng `ditto` sang `/Applications/vflow.app` (có bản cũ thì sao lưu ra `~/.vflow/backup/` trước), gỡ cách ly (`xattr -dr com.apple.quarantine`), kiểm chữ ký. Không dùng `sudo`; thiếu quyền ghi `/Applications` thì dừng. Không tự mở app sau khi cài.

**Lưu ý chữ ký**: bản ad-hoc trong `/Applications/vflow.app` được ký lại độc lập với bản trong `client/build/` mỗi lần cài — macOS sẽ coi là "app khác" và đòi cấp lại quyền macOS (Micro, Theo dõi đầu vào, Trợ năng) cho bản `/Applications`, đó là bản dùng thật.

### Nợ kỹ thuật
`bin/vflow.js` có import TĨNH ở đầu file từ `eval/metrics.js`, `eval/bench.js`, `eval/evaluate.js` (dùng cho lệnh `record`/`bench`/`compare`, không phải `serve`). Vì vậy `bundle-engine.sh` phải đóng gói cả các tệp `.js` ở gốc `eval/` (bỏ `*.test.js`, `eval/reports`, `eval/prompts`, `eval/phowhisper-server`) chứ không chỉ `bin/`+`engine/` như dự kiến ban đầu — nếu không `node bin/vflow.js serve` sẽ lỗi `ERR_MODULE_NOT_FOUND` ngay khi khởi động dù lệnh `serve` không cần các module đó. Nên đổi các import này sang `import()` động trong `bin/vflow.js` (việc của engine/, ngoài phạm vi `client/` — coordinator giao ở task khác).

## Cấu trúc
| Target | Nội dung |
|---|---|
| `VFlowCore` (thư viện, test được) | `Hotkey.swift` máy trạng thái phím (giữ/đúp-khoá/Command Mode/Esc) + phân loại CGEvent; `Audio.swift` bộ chuyển 16 kHz mono Int16 theo khối (sinc cửa sổ Blackman, chống răng cưa), downmix, LE, mức âm, bộ đệm “thử lại”; `Clipboard.swift` chèn bằng clipboard + khôi phục; `SelectionCapture.swift` lấy đoạn đang chọn (AX/⌘C tổng hợp, có kiểm soát) cho Command Mode; `TextMatch.swift` (`VietnameseMatch`) gấp dấu/chuẩn hoá khớp luật engine (`fold`/`normalizeMatch`); `EngineAPI.swift` yêu cầu/phản hồi/ánh xạ lỗi tiếng Việt (transcribe, healthz, dictionary, corrections, snippets, settings, command); `EngineSupervisor.swift` giám sát engine con; `ClientConfig.swift`; `VFlowHome.swift` tôn trọng `VFLOW_HOME`; `History.swift` (`HistoryStore`, `HistoryEntry`, `HistoryGate`) lưu lịch sử chỉ-văn-bản vào `history.jsonl`; `Dictionary.swift`/`DictionaryOrchestration.swift` và `Snippet.swift`/(`SnippetOrchestration` trong cùng tệp) kiểm hợp lệ + mẫu đọc-sửa-ghi chung cho `/v1/dictionary` và `/v1/snippets`; `Settings.swift` (`AppSettings`, `SettingsPatch`, `SettingsValidation`, `EnterAction`) cho `/v1/settings` và quyết định gửi phím Enter; `Dictation.swift`, `Overlay.swift` (gồm trạng thái ghi khoá/Command Mode) quyết định hiển thị; `StatusModel.swift` mô hình thuần dùng CHUNG cho menu và tab Tổng quan (`StatusModel`, `PermissionKind`/`PermissionItem`, `ConflictDetector`/`ConflictText` dò ứng dụng đọc chính tả khác qua `RunningAppsProvider`, `ShowWindowPreference`). |
| `VFlow` (AppKit/SwiftUI mỏng) | event tap, AVAudioEngine, NSPasteboard + ⌘V/Return/⌘C tổng hợp (`TextInserter.swift`: `PasteKeystroke`/`ReturnKeystroke`/`CopyKeystroke`/`AXSelection`), NSPanel thanh trạng thái, `main.swift` (menu ứng dụng, `--open-tab`), `StatusWindow.swift` cửa sổ chính "vflow" (`MainWindowView`, sidebar 5 tab, `HeaderBar` logo đầu cửa sổ), `OverviewView.swift`/`HistoryView.swift`/`DictionaryView.swift`/`SnippetsView.swift`/`SettingsView.swift` (gồm `CloudSettingsSection`) nội dung từng tab, `MainTab.swift`, NSStatusItem + menu (`StatusMenu.swift`, có `setVisible`, dùng `BrandIcon` cho biểu tượng + chấm trạng thái), `BrandIcon.swift` nạp logo-mark từ bundle, `Permissions.swift` (quyền thật, nối `PermissionKind`), `ConflictProvider.swift` (`NSWorkspace` thật), SMAppService. |
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

Biểu tượng thanh menu (`org.aios.vflow`) vẫn còn nhưng giờ chỉ là PHỤ — có công tắc "Hiện biểu tượng trên thanh menu" ở tab Cài đặt (mặc định bật). Trên thanh menu chật (nhiều mục, hoặc notch của MacBook che bớt) macOS có thể tự ẩn biểu tượng mà không báo gì; cách điều khiển CHÍNH không phụ thuộc nó: cửa sổ **"vflow"**, mở được từ Dock, ⌘-Tab, hoặc menu ứng dụng bất cứ lúc nào.

**Đóng cửa sổ chính (nút đỏ) KHÔNG thoát app** — ghi âm bằng phím nóng vẫn hoạt động, engine con vẫn chạy; cửa sổ tự ghi chú điều này ở chân mỗi tab. Thoát hẳn bằng **⌘Q** hoặc menu "vflow › Thoát vflow" (cũng có ở tab Cài đặt). Nếu cửa sổ bị đóng và cần mở lại: bấm Dock, `open client/build/VFlow.app`, hoặc menu thanh trạng thái "Mở cửa sổ vflow".

## Cửa sổ chính "vflow"
Một cửa sổ (`.titled`, đổi cỡ được, nhớ kích thước/vị trí), logo-mark ở đầu nội dung cạnh tên tab (`HeaderBar`, xem mục Logo bên dưới), thanh bên 5 mục (`NavigationSplitView`, điều khiển được bằng bàn phím/VoiceOver):

**Tổng quan** — đúng nội dung cửa sổ trạng thái cũ (M3b), lấy từ CÙNG MỘT mô hình thuần `StatusModel` (VFlowCore) với menu thanh trạng thái nên hai nơi không bao giờ nói khác nhau:
- Dòng hướng dẫn giữ ⌥ trái; **cảnh báo xung đột phím** nếu phát hiện ứng dụng đọc chính tả khác đang chạy (danh sách mặc định trong `VFlowCore.ConflictConfig`, đầu tiên là `com.sonpiaz.haynoi`/Haynoi; dò bằng `NSWorkspace.runningApplications`) — "<tên app> đang chạy: cả hai sẽ phản ứng khi giữ ⌥ trái. Hãy thoát một trong hai."; vflow không tự thoát ứng dụng kia.
- Engine + danh sách model (`loaded:false` luôn kèm `reason`); 3 quyền (Micro, Theo dõi đầu vào, Trợ năng) + nút "Cấp quyền…", tự kiểm lại mỗi 2 giây trong lúc cửa sổ đang hiện; **bộ chọn Chế độ** (dropdown, đủ 6: Tự động/Thường/Làm sạch/**Gọn**/**Lập trình**/Thư) kèm mô tả ngắn cho chế độ đang chọn và dòng nói rõ chế độ này có gửi chữ qua 9Router hay hoàn toàn trong máy; lỗi gần nhất đầy đủ; "Thử lại lần cuối", "Khởi động lại engine", "Mở thư mục dữ liệu".

**Lịch sử** — các câu đã đọc chính tả (mới nhất trên cùng; thời gian, app đích, chế độ, model, văn bản). CHỈ lưu văn bản (`text_raw`, `text`, mode, app bundle id, model, audio_ms, timings) — **tuyệt đối không có âm thanh**; mục Command Mode lưu dạng `mode: "command:edit"|"command:draft"`, `text_raw` = lệnh đã nói, `text` = kết quả — **không bao giờ lưu đoạn đang chọn**. Lưu `<VFLOW_HOME>/history.jsonl` (JSONL, quyền 0600, ghi nối nguyên tử + tự dọn giữ tối đa 500 mục/30 ngày, dòng hỏng bị bỏ qua và đếm chứ không làm sập — xem `VFlowCore.HistoryStore`). Tìm kiếm, Sao chép, "Sửa…" (mở hộp sửa văn bản cuối; Lưu ⇒ `POST /v1/corrections` ⇒ hiện gợi ý `{term, spoken}`, CHỈ ghi vào từ điển khi người dùng bấm xác nhận từng gợi ý; không gợi ý thì nói rõ "Không có gợi ý"; không tự dán lại văn bản đã sửa vào đâu cả), xoá một mục, "Xoá toàn bộ lịch sử…" (xác nhận). Công tắc "Lưu lịch sử" ở tab Cài đặt (mặc định bật; tắt ⇒ không ghi mục mới, không xoá mục cũ). Kết quả lỗi/im lặng không bao giờ vào lịch sử.

**Từ điển** — đọc `GET /v1/dictionary`, thêm/sửa/xoá qua `PUT /v1/dictionary` kiểu **đọc-sửa-ghi** (đọc lại ngay trước khi ghi, xem `VFlowCore.DictionaryOrchestration`, để không đè thay đổi của engine/cửa sổ khác giữa chừng). Kiểm hợp lệ phía client khớp luật engine (`VFlowCore.DictionaryValidation`: spoken 1–20 chuỗi ≤100 ký tự, term không trùng, tối đa 5000 mục) trước khi gửi; lỗi `bad_request` của engine hiện nguyên văn (đã là tiếng Việt theo contract), không nuốt. Engine không chạy ⇒ nói rõ bằng chữ đỏ, KHÔNG hiện danh sách rỗng giả.

**Snippets** — đọc `GET /v1/snippets`, thêm/sửa/xoá qua `PUT /v1/snippets` kiểu đọc-sửa-ghi giống Từ điển (xem `VFlowCore.SnippetOrchestration`). Mỗi mục: trigger, xem trước nội dung, số lần dùng. Kiểm hợp lệ phía client khớp luật engine (`VFlowCore.SnippetValidation`: trigger 1–60 ký tự, text 1–5.000, không trùng sau khi chuẩn hoá bỏ dấu thanh/hoa thường/dấu câu — `VFlowCore.VietnameseMatch`, tối đa 500 mục). Dòng hướng dẫn: nói đúng cả câu bằng trigger, hoặc "chèn \<trigger\>" trong câu.

**Cài đặt** — chế độ mặc định (dùng chung `ModeSection` với Tổng quan); mục **"Đám mây (9Router)"** (`CloudSettingsSection`): công tắc "Cho phép gửi chữ qua 9Router" (`cloud_llm`), ô "Model" (`llm_model`, trống = chưa đặt, kèm cảnh báo Gọn/Thư/Command Mode sẽ không chạy), ô "Thời gian chờ (giây)" (`llm_timeout_ms`, 1–30 s), công tắc "Nhấn Enter bằng giọng" (`actions_enabled`) — đọc/ghi qua `GET/PUT /v1/settings`, hiệu lực ngay, lỗi `bad_request` hiện tiếng Việt, "Đang chờ engine khởi động…" khi chưa sẵn sàng; câu ghi chú "Âm thanh không bao giờ rời máy. Chế độ Gọn, Thư và Command Mode gửi CHỮ (không phải âm thanh) qua 9Router tới nhà cung cấp model."; Bật khi đăng nhập, Hiện cửa sổ khi mở app, Hiện biểu tượng trên thanh menu, Lưu lịch sử + "Xoá toàn bộ lịch sử…", đường dẫn dữ liệu hiện dùng (tôn trọng `VFLOW_HOME`), phiên bản, Thoát vflow.

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
- NSPanel không viền, không lấy focus, bỏ qua chuột, nổi trên mọi Space/toàn màn hình, giữa đáy màn hình có con trỏ chuột (phía trên Dock). Logo-mark cạnh chữ trạng thái; 6 trạng thái bằng SF Symbols: "Đang nghe" (`mic.fill` + thanh mức âm), "Đang nghe (đã khoá…)" (ghi hands-free), "Đang nghe lệnh" (Command Mode, `command`), "Đang dịch" (`waveform`), "Xong" (`checkmark.circle.fill`), "Lỗi: …" (`exclamationmark.triangle.fill`); thông báo ngắn "Đã huỷ"/"Không nghe thấy gì" (`info.circle`); cảnh báo "còn ~20s" ở giây thứ 100 rồi tự quay lại trạng thái đang nghe. Chữ 13 pt, tôn trọng Reduce Motion (thanh mức không hoạt ảnh), nhãn VoiceOver và thông báo VoiceOver khi đổi trạng thái (trừ lúc đang nghe).
- Menu bar: biểu tượng là logo-mark + chấm trạng thái phủ góc dưới-phải khi đang nghe/dịch/lỗi (`VFlow.BrandIcon`, không có bundle đóng gói thì rơi về SF Symbol cũ); tooltip/nhãn trợ năng luôn mô tả đúng trạng thái bằng chữ. "Mở cửa sổ vflow" (đầu menu); trạng thái engine; cảnh báo xung đột phím (nếu có); lỗi gần nhất (đầy đủ); quyền thiếu; Chế độ (đủ 6, nhớ trong UserDefaults `org.aios.vflow`); Model (từ `/healthz`, model `loaded:false` hiện kèm lý do); Thử lại lần cuối; Khởi động lại engine (khi đã bỏ cuộc); Bật khi đăng nhập (SMAppService); Mở thư mục dữ liệu (`~/.vflow`); "Hướng dẫn cấp quyền…" (mở cửa sổ "vflow"); Thoát. Công tắc ẩn/hiện biểu tượng này nằm ở tab Cài đặt của cửa sổ chính.

## Logo
`client/Resources/branding/logo-main.png` (tròn cam, chữ V đen, 1024², do chủ dự án cung cấp, KHÔNG sửa) ⇒ `scripts/make-icon.sh` thu nhỏ vào vùng an toàn ≈824/1024 ở giữa canvas 1024 (CoreGraphics, `scripts/pad-icon.swift`) rồi `sips -z`/`iconutil -c icns` ra `client/Resources/AppIcon.icns` (biểu tượng Dock/Finder/Cmd-Tab/Giới thiệu, qua `CFBundleIconFile` trong Info.plist). `client/Resources/branding/logo-mark.png` (chữ V cam trên nền trong suốt, 1024², KHÔNG sửa) ⇒ `sips -z` ra `menubar-mark-18{,@2x,@3x}.png` (18/36/54 px) dùng cho biểu tượng thanh menu, đầu cửa sổ chính (`HeaderBar`, ~28pt) và cạnh chữ trên thanh trạng thái ghi âm (`VFlow.BrandIcon`, nạp từ `Bundle.main.resourcePath`). Trạng thái (nghe/dịch/lỗi) không dựa riêng vào màu: biểu tượng thanh menu phủ thêm một chấm nhỏ (hình, không chỉ màu) ở góc dưới-phải khi đang nghe/dịch/lỗi, cộng tooltip/nhãn trợ năng luôn mô tả bằng chữ. Chạy lại `scripts/make-icon.sh` khi đổi logo; `build-app.sh` chỉ COPY các tệp sinh ra (không tự sinh).

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
