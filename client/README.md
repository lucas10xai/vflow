# vflow — client macOS (menu bar)

Giữ **⌥ Option trái**, nói, nhả phím ⇒ chữ được dán vào ô đang gõ ở mọi ứng dụng (kể cả Terminal). Client chỉ nói chuyện với engine cục bộ `http://127.0.0.1:7611` theo `contract/engine-api.md`; không mạng ngoài, không analytics, không tự cập nhật, không thư viện bên thứ ba.

## Dựng và chạy
```sh
client/scripts/build-app.sh            # ⇒ client/build/VFlow.app (release, ký ad-hoc, codesign --verify)
client/scripts/build-app.sh --clean    # như trên rồi xoá client/.build (~ vài trăm MB)
open client/build/VFlow.app
cd client && swift test                # test logic thuần (VFlowCore)
```
Yêu cầu: macOS 14+, Xcode/Swift 6. Cờ dòng lệnh của nhị phân `VFlow.app/Contents/MacOS/VFlow`:
- `--demo-overlay ghi|dich|xong|loi [--demo-seconds N]`: chỉ hiện thanh trạng thái ở một trạng thái (để chụp ảnh), không chạy engine/phím nóng.
- `--no-prompt`: không bật hộp thoại xin quyền (dùng khi chạy thử tự động); vẫn kiểm và báo trạng thái quyền.

## Cấu trúc
| Target | Nội dung |
|---|---|
| `VFlowCore` (thư viện, test được) | `Hotkey.swift` máy trạng thái phím + phân loại CGEvent; `Audio.swift` bộ chuyển 16 kHz mono Int16 theo khối (sinc cửa sổ Blackman, chống răng cưa), downmix, LE, mức âm, bộ đệm “thử lại”; `Clipboard.swift` chèn bằng clipboard + khôi phục; `EngineAPI.swift` yêu cầu/phản hồi/ánh xạ lỗi tiếng Việt; `EngineSupervisor.swift` giám sát engine con; `ClientConfig.swift`; `Dictation.swift`, `Overlay.swift` quyết định hiển thị; `StatusModel.swift` mô hình thuần dùng CHUNG cho menu và cửa sổ trạng thái (`StatusModel`, `PermissionKind`/`PermissionItem`, `ConflictDetector`/`ConflictText` dò ứng dụng đọc chính tả khác qua `RunningAppsProvider`, `ShowWindowPreference`). |
| `VFlow` (AppKit/SwiftUI mỏng) | event tap, AVAudioEngine, NSPasteboard + ⌘V, NSPanel thanh trạng thái, `StatusWindow.swift` cửa sổ “vflow” (điều khiển chính), NSStatusItem + menu, `Permissions.swift` (quyền thật, nối `PermissionKind`), `ConflictProvider.swift` (`NSWorkspace` thật), SMAppService. |
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
- Event tap **chỉ nghe** (`listenOnly`): vflow không chặn hay sửa phím nào, ⌥ vẫn làm việc bình thường ở ứng dụng.
- Giữ ⌥ trái ≥ 200 ms (không kèm ⌘/⌃/⇧/⌥ phải) ⇒ bắt đầu ghi; nhả ⇒ gửi. Chạm nhanh < 200 ms ⇒ bỏ qua hoàn toàn.
- Trong lúc chờ ngưỡng: bấm phím khác/bổ trợ khác/chuột ⇒ coi là tổ hợp (⌥←, ⌥-click, ký tự đặc biệt) và bỏ qua tới khi nhả ⌥.
- Trong lúc ghi: phím khác, ⌥ phải, ⌘, ⌃, ⇧, fn, Caps Lock, bấm chuột ⇒ **huỷ** (bỏ âm thanh, hiện “Đã huỷ”).
- Ghi tối đa 120 s rồi tự gửi. Đang dịch thì không nhận lần ghi mới (không chồng). Mất sự kiện nhả phím ⇒ phát hiện qua trạng thái phím thật mỗi 50 ms; tap bị hệ thống tắt ⇒ bật lại và huỷ lần ghi; đang dịch quá 200 s ⇒ bỏ yêu cầu, về rảnh.

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
- **Bản ký ad-hoc**: TCC gắn quyền với chữ ký; mỗi lần chạy lại `build-app.sh` có thể tạo chữ ký mới ⇒ macOS có thể đòi cấp lại (bật/tắt lại vflow trong danh sách). vflow không bao giờ sửa/xoá cơ sở dữ liệu TCC.

## Không thấy biểu tượng?
Trên thanh menu chật (nhiều mục, hoặc notch của MacBook che bớt), macOS có thể **ẩn biểu tượng `org.aios.vflow`** mà không báo gì — app vẫn chạy bình thường, chỉ là không thấy để bấm vào. Cách điều khiển CHÍNH vì vậy KHÔNG phụ thuộc biểu tượng này: cửa sổ **“vflow”** (`StatusWindow`).
- Mặc định cửa sổ tự hiện khi mở app (công tắc “Hiện cửa sổ này khi mở app” trong chính cửa sổ, lưu UserDefaults, tắt được nếu không muốn).
- Chạy `open client/build/VFlow.app` lần nữa khi app đang chạy ⇒ **không** mở tiến trình thứ hai, chỉ đưa cửa sổ lên trước (macOS tự route `open` vào tiến trình đang chạy qua `applicationShouldHandleReopen`).
- Nếu cửa sổ cũng bị đóng: thoát app (Activity Monitor hoặc `pkill -x VFlow` nếu cần) rồi mở lại.
- Đóng cửa sổ **không** thoát app (vẫn còn ở menu bar/Dock-less); thoát hẳn dùng nút “Thoát vflow” trong cửa sổ hoặc mục menu “Thoát vflow”.

## Cửa sổ trạng thái "vflow"
Cửa sổ AppKit/SwiftUI thường (`.titled`, có thể đổi cỡ), giữ activation policy `.accessory` (không có biểu tượng Dock). Nội dung — lấy từ CÙNG MỘT mô hình thuần `StatusModel` (VFlowCore) với menu, nên hai nơi không bao giờ nói khác nhau:
- Dòng hướng dẫn: “Giữ ⌥ Option trái để nói, nhả ra để chữ hiện ở chỗ con trỏ”.
- **Cảnh báo xung đột phím**: nếu phát hiện ứng dụng đọc chính tả khác đang chạy có thể dùng chung ⌥ trái (danh sách mặc định trong `VFlowCore.ConflictConfig`, đầu tiên là `com.sonpiaz.haynoi`/Haynoi; dò bằng `NSWorkspace.runningApplications`), hiện rõ: “<tên app> đang chạy: cả hai sẽ phản ứng khi giữ ⌥ trái. Hãy thoát một trong hai.” vflow không tự thoát ứng dụng kia.
- Engine + danh sách model (như menu; `loaded:false` luôn kèm `reason`).
- 3 quyền (Micro, Theo dõi đầu vào, Trợ năng): biểu tượng + “Đã cấp”/“Chưa cấp” + nút “Cấp quyền…” (mở đúng trang System Settings); tự kiểm lại mỗi 2 giây trong lúc cửa sổ đang hiện.
- Chọn chế độ (auto/normal/clean/email) — dùng chung UserDefaults với menu.
- Lỗi gần nhất, đầy đủ (không cắt ngắn như thanh trạng thái nổi).
- Thao tác: “Thử lại lần cuối” (chỉ bật khi còn âm thanh trong RAM), “Khởi động lại engine”, “Mở thư mục dữ liệu”, công tắc “Hiện cửa sổ này khi mở app” và “Bật khi đăng nhập”, nút “Thoát vflow”.
- Mẹo cuối cửa sổ nhắc lại: nếu không thấy biểu tượng, mở lại app để hiện cửa sổ này.

## Thanh trạng thái nổi và menu
- NSPanel không viền, không lấy focus, bỏ qua chuột, nổi trên mọi Space/toàn màn hình, giữa đáy màn hình có con trỏ chuột (phía trên Dock). 4 trạng thái bằng SF Symbols: “Đang nghe” (`mic.fill` + thanh mức âm), “Đang dịch” (`waveform`), “Xong” (`checkmark.circle.fill`), “Lỗi: …” (`exclamationmark.triangle.fill`); thông báo ngắn “Đã huỷ”/“Không nghe thấy gì” (`info.circle`). Chữ 13 pt, tôn trọng Reduce Motion (thanh mức không hoạt ảnh), nhãn VoiceOver và thông báo VoiceOver khi đổi trạng thái (trừ lúc đang nghe).
- Menu bar: “Mở cửa sổ vflow” (đầu menu); trạng thái engine; cảnh báo xung đột phím (nếu có); lỗi gần nhất (đầy đủ); quyền thiếu; Chế độ (auto/normal/clean/email, nhớ trong UserDefaults `org.aios.vflow`); Model (từ `/healthz`, model `loaded:false` hiện kèm lý do); Thử lại lần cuối; Khởi động lại engine (khi đã bỏ cuộc); Bật khi đăng nhập (SMAppService); Mở thư mục dữ liệu (`~/.vflow`); “Hướng dẫn cấp quyền…” (mở cửa sổ “vflow”); Thoát.

## Rủi ro đã biết
- **Va chạm ⌥**: vì tap chỉ nghe, ký tự gõ bằng ⌥ (å, ∫, “…) vẫn vào ứng dụng như thường. Nếu giữ ⌥ ≥ 200 ms rồi mới bấm phím (⌥← chậm, ⌥-kéo chuột) thì micro bật thoáng qua rồi huỷ (“Đã huỷ”), chỉ báo micro màu cam có thể nháy. Giữ ⌥ một mình (ví dụ chờ để ⌥-click) sẽ bắt đầu ghi.
- Ghi bắt đầu sau 200 ms + thời gian bật AVAudioEngine: tiếng nói ngay lúc vừa bấm có thể bị mất đầu; nên đợi chữ “Đang nghe”.
- ⌘V dùng mã phím ảo 9 (vị trí phím V trên ANSI); bố cục bàn phím khác (Dvorak…) có thể không ra ⌘V.
- Khôi phục clipboard sau 350 ms: ứng dụng đích quá chậm đọc clipboard có thể dán nhầm nội dung cũ. Ứng dụng đích nhận được chữ qua clipboard nên có thể lưu lịch sử dán của riêng nó.
- Chuyển ứng dụng trong lúc “Đang dịch” ⇒ chữ dán vào ứng dụng đang focus lúc có kết quả (bundle id gửi engine là ứng dụng lúc bắt đầu ghi).
