# vflow

**Đọc chính tả tiếng Việt chạy hoàn toàn trong máy Mac của bạn.** Giữ một phím, nói, nhả phím — chữ hiện vào ô đang gõ, ở mọi ứng dụng (kể cả Terminal). Không tài khoản, không đăng nhập, không hạn mức số từ, không đám mây cho phần nhận dạng giọng nói.

> Ý tưởng giống [Haynoi](https://github.com/sonpiaz/haynoi), nhưng dùng model nhận dạng **thuần tiếng Việt** chạy ngay trên CPU của máy.

*English summary is at the [bottom of this page](#english-summary).*

**Trạng thái:** phiên bản `0.1.0`, còn sớm. Dùng được hằng ngày nhưng có [những hạn chế đã biết](#hạn-chế-đã-biết) — đọc kỹ trước khi cài, đặc biệt phần **app chưa được Apple công chứng** và **giấy phép model chỉ cho dùng phi thương mại**.

---

## Tính năng chính

- **Giữ ⌥ Option trái để nói**, nhả ra là chữ được dán vào ô đang gõ. Chạm nhanh thì bỏ qua; **Esc** huỷ ngay.
- **Hands-free:** đúp ⌥ trái để ghi "khoá" — không cần giữ phím, bấm ⌥ một lần nữa để xong. Có tuỳ chọn tự dừng khi im lặng.
- **Command Mode:** giữ ⌥ trái rồi bấm thêm ⌃ trái để ra lệnh bằng lời ("viết lại câu này lịch sự hơn", "soạn thư cảm ơn…") — sửa đoạn đang chọn hoặc soạn mới. *Cần cấu hình máy chủ LLM của bạn (xem [Quyền riêng tư](#quyền-riêng-tư)); mặc định chưa dùng được.*
- **Từ điển cá nhân:** dạy vflow thuật ngữ của bạn ("đi plôi" → *deploy*). Gợi ý từ mới khi bạn hay sửa cùng một chỗ.
- **Dạy từ bằng giọng:** nói thử một từ, xem model nghe ra chữ gì, rồi thêm vào từ điển đúng cách đọc đó.
- **Snippets:** nói một cụm ngắn để chèn đoạn văn mẫu dài (địa chỉ, link lịch hẹn, chữ ký…).
- **Chế độ theo ứng dụng:** Thường · Làm sạch (bỏ "ừm, à") · Lập trình · Gọn · Thư. Chế độ *Tự động* chọn theo ứng dụng đang dùng (Terminal/IDE ⇒ Lập trình, ứng dụng thư/nhắn tin ⇒ Làm sạch…) và **chỉ chọn chế độ chạy trong máy**.
- **Lệnh dấu câu bằng giọng:** "xuống dòng", "dấu phẩy", "mở ngoặc"… (chỉ cụm từ hai từ trở lên, không nhầm với lời nói thường).
- **Ký hiệu theo ngữ cảnh:** trong Terminal/IDE/Slack…, nói "gạch dưới" ⇒ `_`, "hai chấm hai gạch chéo" ⇒ `://`, "a còng" ⇒ `@`. Ngoài các ứng dụng đó, lời nói giữ nguyên.
- **Nói "nhấn enter" ở cuối câu** để tự gửi phím Return sau khi dán.
- **Xem chữ chạy trực tiếp** (chữ mờ tạm thời trên thanh trạng thái khi đang nói, không bao giờ chèn vào ô đích).
- **Thống kê** hoàn toàn cục bộ (số từ, chuỗi ngày, WPM, ứng dụng dùng nhiều) — chỉ là bộ đếm, không lưu nội dung; tắt/xoá được.
- **Lưu âm thanh (tuỳ chọn, MẶC ĐỊNH TẮT):** nếu bạn bật, giọng được lưu trong thư mục dữ liệu trên máy, có giới hạn dung lượng và số ngày, nghe lại/xuất/xoá được.
- Giao diện sáng/tối/theo hệ thống, chọn micro, thanh trạng thái ghi âm đặt dưới màn hình hoặc cạnh notch, lịch sử theo ngày, xuất/nhập dữ liệu.

## Yêu cầu hệ thống

- **Mac chip Apple Silicon** (M1 trở lên). *Chưa hỗ trợ Mac Intel.*
- **macOS 14 (Sonoma) trở lên.**
- Khoảng vài trăm MB dung lượng trống (bản app + model ~26 MB tải về lần đầu) và kết nối mạng **một lần** để tải model.

## Cài đặt

1. Vào trang **Releases** của repo này, tải tệp `vflow-<phiên bản>-macos-arm64.zip` (và tệp `.sha256` đi kèm nếu muốn đối chiếu).
2. Giải nén, kéo **VFlow.app** vào thư mục **Applications**.
3. Lần đầu mở sẽ bị macOS chặn — làm theo mục [Gỡ chặn macOS](#gỡ-chặn-macos-cho-app-chưa-công-chứng) ngay dưới đây.
4. Cấp [3 quyền macOS](#cấp-3-quyền-macos).
5. **Model nhận dạng giọng nói không kèm theo app** (vì giấy phép của model — xem [Giấy phép](#giấy-phép)). Lần đầu mở, vflow hiện cửa sổ **"Cần tải model nhận dạng giọng nói"**: cho biết dung lượng (~26 MB), nguồn (kho chính thức của dự án sherpa-onnx trên GitHub, có kiểm checksum) và giấy phép của model. **Bạn phải bấm "Đồng ý và tải" — tức đồng ý điều kiện CC-BY-NC-ND-4.0 (chỉ dùng phi thương mại) — thì model mới được tải.** Nếu không dùng chế độ Gọn/Thư/Command Mode thì đây là lần duy nhất vflow cần mạng.

Có thể tải model bằng dòng lệnh thay vì qua app (dùng chính Node đi kèm app):

```sh
/Applications/VFlow.app/Contents/Resources/engine/node/bin/node \
  /Applications/VFlow.app/Contents/Resources/engine/bin/vflow.js models pull zipformer-vi-30m
```

## Gỡ chặn macOS cho app chưa công chứng

> **Tóm tắt:** macOS sẽ báo *"không thể xác minh VFlow không chứa phần mềm độc hại"* hoặc *"VFlow đã bị hỏng"*. Đó là bình thường với app này. Cách xử lý ở dưới.

### Vì sao bị chặn?

Với mọi app tải từ Internet, macOS (tính năng **Gatekeeper**) chỉ cho chạy thẳng nếu app được ký bằng chứng chỉ của **Apple Developer Program** (99 USD/năm) *và* được Apple **công chứng** (quét tự động). vflow là dự án mã nguồn mở miễn phí và **hiện chưa mua chứng chỉ đó**, nên app chỉ được ký ở mức cơ bản (ad-hoc) — macOS không có cơ sở để "tin tên tác giả" và mặc định chặn.

Bị chặn **không có nghĩa** là app đã bị phát hiện có hại; chỉ có nghĩa là **Apple chưa kiểm tra nó**.

### Cách 1 — qua Cài đặt hệ thống (macOS 15 Sequoia trở lên; dùng được cả trên macOS 14)

1. Bấm đúp **VFlow.app** một lần. Khi hộp thoại chặn hiện ra, bấm **Xong** (đừng bấm "Chuyển vào thùng rác").
2. Mở **Cài đặt hệ thống › Quyền riêng tư & Bảo mật**, kéo xuống mục **Bảo mật**.
3. Bạn sẽ thấy dòng *"VFlow" đã bị chặn…* — bấm **Vẫn mở** (*Open Anyway*), nhập mật khẩu hoặc Touch ID.
4. Mở lại VFlow.app, bấm **Mở**.

### Cách 2 — chuột phải, Mở (chỉ macOS 14 Sonoma)

Giữ phím ⌃ Control và bấm vào VFlow.app (hoặc bấm chuột phải) › **Mở** › **Mở**. *Từ macOS 15, Apple đã bỏ lối tắt này; hãy dùng Cách 1.*

### Cách 3 — dòng lệnh (nếu báo "đã bị hỏng" hoặc không thấy nút "Vẫn mở")

Mở Terminal và chạy (đổi đường dẫn nếu bạn để app chỗ khác):

```sh
xattr -dr com.apple.quarantine /Applications/VFlow.app
```

Lệnh này chỉ **gỡ nhãn "tải từ Internet"** (`com.apple.quarantine`) khỏi app. Nó không tắt Gatekeeper của máy, không sửa app, không cần `sudo`.

### Rủi ro và vì sao vẫn có thể yên tâm

- **Rủi ro thật:** khi bạn gỡ chặn, bạn đang tự quyết định tin app này mà không có bên thứ ba (Apple) xác nhận. Chỉ làm khi bạn tải từ **trang Releases chính thức của repo này** — đừng gỡ chặn cho tệp lấy từ nơi khác, kể cả khi nó tên "vflow".
- **Mã nguồn mở:** toàn bộ mã nằm ở repo này, ai cũng đọc được. Bản phát hành được GitHub Actions dựng từ mã đã gắn thẻ (workflow nằm trong `.github/workflows/`), kèm SHA-256 để bạn đối chiếu bằng `shasum -a 256`.
- **Tự dựng được:** không muốn tin bản dựng sẵn thì [tự biên dịch](#tự-biên-dịch) từ cùng mã nguồn; app tự dựng trên máy bạn không bị gắn nhãn "tải từ Internet" nên không bị chặn.
- **Hai quyền mạnh:** app cần quyền Theo dõi đầu vào và Trợ năng (xem dưới). Mã nguồn mở là cách để bạn tự kiểm tra app chỉ dùng chúng để "nghe phím giữ-để-nói" và "gửi ⌘V". Lưu ý: dự án chưa có kiểm toán bảo mật độc lập.

> Mỗi lần cập nhật sang bản mới (chữ ký ad-hoc đổi), macOS có thể đòi bạn **cấp lại 3 quyền** — nếu vflow không nhận phím sau khi cập nhật, vào Cài đặt hệ thống, tắt rồi bật lại vflow trong từng mục quyền (hoặc bấm dấu − để xoá rồi mở lại app để cấp mới).

## Cấp 3 quyền macOS

Vào **Cài đặt hệ thống › Quyền riêng tư & Bảo mật** và bật **vflow** ở ba mục. Tab Tổng quan trong app hiện trạng thái từng quyền và có nút mở đúng trang.

| Quyền | Để làm gì |
|---|---|
| **Micro** | Ghi giọng nói của bạn khi giữ phím. |
| **Theo dõi đầu vào** (Input Monitoring) | Nghe phím ⌥ trái (giữ-để-nói) và Esc ở mọi ứng dụng. vflow chỉ *nghe*, không chặn hay sửa phím nào. |
| **Trợ năng** (Accessibility) | Gửi lệnh dán ⌘V (và Return khi bạn nói "nhấn enter") vào ô đang gõ. |

vflow **không** cần quyền Ghi màn hình.

## Tự biên dịch

Yêu cầu: Mac Apple Silicon, macOS 14+, Xcode 16 trở lên (Swift 6), Node.js 22+, kết nối mạng.

```sh
git clone <địa chỉ repo này> vflow
cd vflow
npm ci                                  # cài phụ thuộc của engine (sherpa-onnx-node)
npm test                                # test engine
(cd client && swift test)               # test client
client/scripts/build-app.sh --no-model  # dựng client/build/VFlow.app, KHÔNG kèm model
open client/build/VFlow.app
```

Rồi tải model như mục [Cài đặt](#cài-đặt) bước 5. App tự dựng không bị chặn bởi Gatekeeper. Chi tiết dành cho lập trình viên: [`client/README.md`](client/README.md) và [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Quyền riêng tư

- **Âm thanh không rời máy.** Giọng nói được ghi vào bộ nhớ, chuyển thành chữ bằng model chạy trong máy, rồi bỏ. **Mặc định không ghi xuống đĩa.** *Lưu âm thanh* là tuỳ chọn do bạn bật (mặc định TẮT), lưu cục bộ trong thư mục dữ liệu `~/.vflow/audio` (quyền chỉ chủ sở hữu đọc được), có giới hạn MB và số ngày, xoá hết được bằng một nút.
- **Engine chỉ nghe `127.0.0.1`** (không bao giờ mở ra mạng), mọi yêu cầu cần token ngẫu nhiên lưu trong `~/.vflow`. Không telemetry, không phân tích, không tự cập nhật, không tài khoản.
- **Mạng chỉ dùng khi:** (1) tải model lần đầu; (2) bạn **tự bật** chế độ dùng LLM — xem tiếp.
- **Chế độ Gọn, Thư và Command Mode gửi VĂN BẢN** (không phải âm thanh) tới một máy chủ **tương thích OpenAI** (`/chat/completions`) mà **bạn tự chỉ định** (mặc định trỏ về `http://127.0.0.1:20128/v1` — một router chạy trên máy bạn, nếu có) — và chỉ khi **bạn tự đặt tên model và tự đặt khoá** (tệp `~/.vflow/rewrite.key`). Chưa cấu hình thì các chế độ này không gửi gì cả: Gọn/Thư rơi về bản xử lý trong máy và báo rõ, Command Mode báo lỗi. Có công tắc **Cho phép gửi chữ** để tắt hẳn. Bạn chịu trách nhiệm về nơi văn bản của mình tới ở máy chủ đó. vflow **không** kèm khoá hay dịch vụ nào.
- Chế độ **Tự động** mặc định **không bao giờ** gọi LLM.
- **Lịch sử chữ** (các câu đã đọc) lưu trong máy, bật mặc định, tắt/xoá được ở Cài đặt. **Thống kê** chỉ là bộ đếm số, không có nội dung. Log của engine chỉ chứa mã, thời lượng — không chứa văn bản giọng nói.
- Xuất dữ liệu/chẩn đoán không bao giờ chứa token, khoá hay âm thanh.

## Giấy phép

- **Mã nguồn vflow: [Apache License 2.0](LICENSE)** — dùng, sửa, phân phối lại, kể cả thương mại, theo điều khoản Apache-2.0.
- **Model nhận dạng giọng nói `zipformer-vi-30m` KHÔNG thuộc Apache-2.0.** Nó là [Zipformer-30M-RNNT-6000h của tác giả hynt](https://huggingface.co/hynt/Zipformer-30M-RNNT-6000h), giấy phép **CC-BY-NC-ND-4.0**: **cấm dùng thương mại** và **cấm phát hành bản sửa đổi**. Vì vậy bản phát hành của vflow không kèm model, và **bạn không được dùng vflow cùng model này cho mục đích thương mại** nếu chưa có giấy phép riêng từ tác giả model.
- Muốn dùng thương mại: đổi sang model có giấy phép phù hợp (ví dụ [PhoWhisper của VinAI](https://huggingface.co/vinai/PhoWhisper-large), BSD-3-Clause — vflow có sẵn đường chạy PhoWhisper qua máy chủ riêng, xem [`contract/remote-stt.md`](contract/remote-stt.md)) hoặc xin phép tác giả model.
- Danh sách đầy đủ thành phần bên thứ ba và giấy phép: [`NOTICE`](NOTICE). Lý do chọn giấy phép: [`docs/license-decision.md`](docs/license-decision.md).

## Hạn chế đã biết

- **Chưa có số đo chất lượng công khai.** Dự án chưa công bố WER/độ chính xác đo bằng bộ dữ liệu độc lập; đừng kỳ vọng con số nào. Model thuần Việt thường **kém ở từ tiếng Anh xen giữa câu** (bù một phần bằng từ điển cá nhân).
- **Chỉ Apple Silicon, macOS 14+.** Chưa có bản Intel, Windows, Linux.
- **App chưa được Apple công chứng** (xem mục gỡ chặn) và **chữ ký ad-hoc** nên có thể phải cấp lại quyền sau mỗi lần cập nhật.
- **Model chỉ dùng phi thương mại** (xem Giấy phép).
- Phím giữ-để-nói mặc định là ⌥ trái; có thể đổi trong Cài đặt nhưng chỉ chọn trong vài phím bổ trợ đơn.
- Ký hiệu theo ngữ cảnh chỉ có trong danh sách ứng dụng cố định; "gạch chéo" dính hai phía nên đường dẫn tuyệt đối phải sửa tay.
- Chưa có cập nhật tự động — bạn tự tải bản mới ở trang Releases.

## Đóng góp và báo lỗi bảo mật

- Muốn đóng góp: xem [`CONTRIBUTING.md`](CONTRIBUTING.md).
- Phát hiện lỗ hổng bảo mật: **đừng mở issue công khai**, xem [`SECURITY.md`](SECURITY.md).
- Lịch sử thay đổi: [`CHANGELOG.md`](CHANGELOG.md). Quy trình phát hành: [`docs/release-process.md`](docs/release-process.md).

Thiết kế và hợp đồng API giữa các phần: [`docs/specs/2026-10-26-vflow-design.md`](docs/specs/2026-10-26-vflow-design.md), [`contract/`](contract/).

---

## English summary

**vflow** is a fully on-device Vietnamese dictation tool for macOS: hold the left ⌥ key, speak, release — the text is pasted into whatever field you are typing in. No account, no word limit, no cloud speech recognition. It runs a Vietnamese Zipformer model on the CPU through sherpa-onnx.

- **Requirements:** Apple Silicon Mac, macOS 14+. Intel is not supported.
- **Features:** hold-to-talk, hands-free mode, Command Mode (needs your own OpenAI-compatible LLM endpoint), personal dictionary, teach-by-voice, snippets, per-app modes, voice punctuation, context-aware symbols for terminals/IDEs, local-only stats, optional audio history (**off by default**).
- **Privacy:** audio never leaves your machine and is not written to disk by default. Only the *Tidy*, *Email* and *Command* modes send **text** (never audio) to an OpenAI-compatible server **you** configure, and only if you set a model name and key yourself. No telemetry, no auto-update.
- **Install:** download the `.zip` from the Releases page. The app is **not notarized by Apple** (no paid Developer ID yet), so macOS will block it on first launch: use *System Settings › Privacy & Security › Open Anyway*, or run `xattr -dr com.apple.quarantine /Applications/VFlow.app`. Only do this for files downloaded from this repository's official Releases page. Or [build it yourself](#tự-biên-dịch).
- **Model:** not bundled in public releases. You download it on first run and must accept its license.
- **License:** source code is **Apache-2.0**. The speech model `zipformer-vi-30m` is **CC-BY-NC-ND-4.0** (by hynt): **non-commercial use only, no modified redistribution**. For commercial use, switch to a commercially licensed model (e.g. VinAI PhoWhisper, BSD-3-Clause) or obtain permission from the model's author. See [`NOTICE`](NOTICE) and [`docs/license-decision.md`](docs/license-decision.md).
- **Known limitations:** no public accuracy benchmark yet; Apple Silicon only; not notarized; a pure-Vietnamese model is weaker on English words mixed into sentences.
