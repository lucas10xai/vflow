# Quyết định giấy phép

Ngày ghi: 2026-10-27 · Người quyết định: Nguyễn Văn An (chủ dự án) · Soạn: worker O3

> Đây là ghi chép kỹ thuật về lý do và ràng buộc, **không phải tư vấn pháp lý**. Việc nào cần chắc chắn về pháp lý (đặc biệt về model, mục 3) nên hỏi luật sư hoặc hỏi thẳng tác giả model.

## 1. Quyết định

| Phần | Giấy phép | Ghi chú |
|---|---|---|
| Mã nguồn vflow (engine, client, script, tài liệu của repo) | **Apache License 2.0** | Tệp `LICENSE` (toàn văn chuẩn, đã đối chiếu sha256 với bản ASF/sherpa-onnx), bản quyền "Nguyễn Văn An"; danh sách bên thứ ba ở `NOTICE`. |
| Model nhận dạng `zipformer-vi-30m` | **CC-BY-NC-ND-4.0** (của tác giả model, không phải của vflow) | **KHÔNG kèm theo bản phát hành công khai.** Người dùng tự tải lần đầu và phải đồng ý điều kiện. |
| Phát hành | GitHub Releases, zip `macos-arm64`, ký ad-hoc, **chưa công chứng** | Chưa mua Apple Developer Program. Xem `docs/release-process.md`. |

## 2. Vì sao Apache-2.0 (không phải MIT hay GPL)

**So với MIT**
- Apache-2.0 có **cấp quyền bằng sáng chế** rõ ràng (điều 3) và điều khoản chấm dứt quyền nếu người dùng kiện về bằng sáng chế liên quan. MIT im lặng về bằng sáng chế. App này chạy trên ngăn xếp Apache-2.0/MIT (sherpa-onnx, ONNX Runtime) và có thể được các bên khác dùng/đóng gói lại; có điều khoản bằng sáng chế rõ ràng là lợi thế.
- **Đồng bộ với phụ thuộc chính:** sherpa-onnx là Apache-2.0, nên cùng giấy phép tránh phải giải thích sự khác biệt.
- Điều 5 biến mọi đóng góp gửi vào dự án thành đóng góp theo cùng giấy phép (không cần ký CLA riêng) — phù hợp dự án cá nhân nhỏ.
- Cái giá: dài hơn MIT; người phân phối lại phải giữ `LICENSE`/`NOTICE` và ghi chú thay đổi (điều 4). Chấp nhận được.

**So với GPL (v2/v3, hoặc AGPL)**
- Mục tiêu là ai cũng dùng/đóng gói/sửa được với ràng buộc thấp nhất. GPL (copyleft) bắt các sản phẩm phái sinh phải mở mã — phù hợp nếu muốn *chống* bản đóng kín, nhưng làm khó người muốn nhúng engine vào công cụ khác, và **không giải quyết** vấn đề thật nhất của dự án (model, mục 3).
- Cái giá của việc không chọn copyleft: ai đó có thể lấy mã vflow, sửa và phát hành bản đóng kín. Chủ dự án đã chấp nhận điều này.
- Apache-2.0 → GPL-3.0 tương thích một chiều, nên nếu sau này muốn đổi hướng sang copyleft cho bản mới thì vẫn làm được (bản đã phát hành vẫn giữ Apache-2.0).

**Không chọn:** giấy phép "phi thương mại" cho cả mã (như CC-BY-NC) — sẽ không còn là mã nguồn mở theo định nghĩa OSI và chặn nhiều cách dùng chính đáng; ràng buộc phi thương mại hiện chỉ nằm ở model, đúng chỗ nó phát sinh.

## 3. Ràng buộc từ model (điểm quan trọng nhất)

Model mặc định là **Zipformer-30M-RNNT-6000h** của tác giả hynt. Trang model trên Hugging Face ghi giấy phép **`cc-by-nc-nd-4.0`** (đối chiếu ngày 2026-10-27; engine cũng ghi cùng giá trị trong `engine/stt/registry.js` và `manifest.json`):

- **NC (NonCommercial):** cấm dùng cho mục đích thương mại. Ranh giới "thương mại" có thể gây tranh cãi (ví dụ dùng ở công ty có doanh thu, dùng trong sản phẩm/dịch vụ bán tiền). Hướng dẫn chính thức của Creative Commons: <https://creativecommons.org/faq/#does-my-use-violate-the-noncommercial-clause-of-the-licenses>. Ứng xử thận trọng: coi mọi việc dùng liên quan tới doanh thu là cần xin phép.
- **ND (NoDerivatives):** cấm phát hành bản sửa đổi của model. vflow không sửa model, không đăng lại model; chỉ tải từ nguồn công khai về máy người dùng.
  - **Câu hỏi chưa có đáp án chắc chắn:** gói `sherpa-onnx-zipformer-vi-30M-int8-…` là bản ONNX **int8** do dự án sherpa-onnx chuyển đổi/đăng — có phải "bản sửa đổi" theo CC hay không? vflow không tự đánh giá và không đăng lại gói này; rủi ro (nếu có) nằm ở bên đăng gói. Cách giảm rủi ro: hỏi/xin xác nhận bằng văn bản từ tác giả hynt.
- **BY (Attribution):** phải ghi công — đã làm trong `NOTICE`, README, màn hình tải model, `LICENSES/` trong app.

**Hệ quả cho dự án:**
1. Bản phát hành công khai **không kèm model** (cờ `build-app.sh --no-model`; workflow phát hành tự kiểm gói không có tệp `.onnx`). Bản dựng mặc định (không cờ) vẫn kèm model cho chủ dự án dùng cá nhân và **không được đăng công khai**.
2. Màn hình tải model lần đầu bắt buộc người dùng bấm đồng ý giấy phép model trước khi tải.
3. README và `NOTICE` nói thẳng: **mã Apache-2.0 nhưng model phi thương mại**. Nhãn "mã nguồn mở" áp dụng cho mã; **cấu hình mặc định nguyên bản (vflow + model này) KHÔNG dùng được cho mục đích thương mại.**
4. Giấy phép mã Apache-2.0 **không "cứu"** được giấy phép model: ai dùng thương mại vẫn vi phạm điều khoản model dù mã hợp lệ.

## 4. Đường đi nếu sau này muốn thương mại (hoặc cho người khác dùng thương mại)

Chọn một trong các hướng (có thể kết hợp):

| Hướng | Việc cần làm | Rủi ro / cần kiểm |
|---|---|---|
| **A. Xin giấy phép riêng từ tác giả model (hynt)** | Liên hệ qua Hugging Face; xin văn bản cho phép dùng/phát hành lại thương mại (hoặc đổi sang giấy phép cho phép thương mại). | Phụ thuộc thiện chí tác giả; có thể có phí/điều kiện. Lưu văn bản trong `docs/`. |
| **B. Đổi sang model có giấy phép cho phép thương mại** | Thêm model vào `engine/stt/registry.js` với đúng `license`; chạy lại `eval/` (WER/CER/RTF) trên bộ câu thật để so với model hiện tại; đổi `DEFAULT_MODEL`; cập nhật `NOTICE`, README, màn hình tải model. Ứng viên đã biết: **PhoWhisper (VinAI)** — thẻ model ghi `bsd-3-clause` (đối chiếu 2026-10-27), vflow đã có đường chạy từ xa (`contract/remote-stt.md`). | Whisper-lớn nặng, khó chạy thời gian thực trên CPU; cần kiểm bản nhỏ hơn (tiny/base/small/medium) về chất lượng/tốc độ. Giấy phép thẻ model **không bảo đảm** quyền với dữ liệu huấn luyện — kiểm thêm. |
| **C. Tự huấn luyện/tinh chỉnh model trên dữ liệu có giấy phép phù hợp** | Dự án riêng, tốn công và dữ liệu. | Quyền với dữ liệu; chi phí GPU. |

Trong lúc chuyển đổi: giữ nguyên quy tắc "không kèm model có giấy phép hạn chế trong bản công khai".

## 5. Cách đã tự kiểm giấy phép từng phụ thuộc (2026-10-27)

| Thành phần | Cách kiểm | Kết quả |
|---|---|---|
| `sherpa-onnx-node` 2.0.0, `sherpa-onnx-darwin-arm64` 2.0.0 | `node -e "console.log(require('./node_modules/<gói>/package.json').license)"`; đối chiếu `package-lock.json`; tải `LICENSE` của k2-fsa/sherpa-onnx | `Apache-2.0` ở cả hai; LICENSE gốc trùng sha256 với văn bản Apache-2.0 chuẩn |
| ONNX Runtime (trong `libonnxruntime.dylib` của gói trên) | `strings libonnxruntime.dylib` tìm chuỗi phiên bản; tải `LICENSE` của microsoft/onnxruntime | Chuỗi phiên bản `1.28.2`; giấy phép **MIT** ("Copyright (c) Microsoft Corporation") |
| Node.js 22 (nhúng trong app) | Đọc `LICENSE` trong bản tarball chính thức đã cache `client/.cache/node-v22.*-darwin-arm64/` | MIT, kèm danh sách giấy phép thành phần bên trong (V8, OpenSSL, ICU…) |
| Model `zipformer-vi-30m` | `https://huggingface.co/api/models/hynt/Zipformer-30M-RNNT-6000h`; `manifest.json` do `vflow models pull` ghi | `cc-by-nc-nd-4.0` |
| PhoWhisper (tuỳ chọn, không đi kèm) | `https://huggingface.co/api/models/vinai/PhoWhisper-large` | `bsd-3-clause` |
| Client Swift | `client/Package.swift` | Không có dependency bên thứ ba; chỉ framework Apple |

Khi thêm phụ thuộc mới: kiểm bằng cách tương tự, ghi vào `NOTICE` và bảng này **trong cùng PR**.

## 6. Việc còn mở

- Liên hệ tác giả model để xác nhận bằng văn bản các điểm ở mục 3 (đặc biệt "ND" với gói int8) — chưa làm.
- `ThirdPartyNotices.txt` của ONNX Runtime (thông báo cho các thư viện nằm bên trong ONNX Runtime) hiện **chưa** được chép vào `VFlow.app/Contents/Resources/LICENSES/` (script đóng gói chỉ chép `LICENSE`) — nên bổ sung ở `client/scripts/bundle-engine.sh`.
- Quyền tác giả đối với phần mã được viết với sự hỗ trợ của công cụ AI chưa được đánh giá pháp lý riêng.
- Homebrew Cask: xem `docs/release-process.md`, mục "Đường tới Homebrew".
