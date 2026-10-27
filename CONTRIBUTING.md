# Đóng góp cho vflow

Cảm ơn bạn đã quan tâm. vflow là dự án nhỏ do một cá nhân duy trì, nên xin hãy **mở issue trước** khi làm thay đổi lớn để thống nhất hướng đi.

## Cấu trúc repo

```
engine/       engine Node (ESM + JSDoc): stt/ (sherpa-onnx), post/ (từ điển, chế độ, LLM), server/ (HTTP 127.0.0.1)
client/       app macOS (Swift 6): VFlowCore (logic thuần, test được) + VFlow (AppKit/SwiftUI mỏng)
contract/     hợp đồng API giữa client và engine — đổi hành vi API thì đổi cả ở đây
eval/         công cụ đo WER/CER/RTF, bộ câu thoại mẫu
scripts/      công cụ phát triển
docs/         đặc tả thiết kế, quy trình phát hành, quyết định giấy phép
```

## Dựng và chạy test

Yêu cầu: Mac Apple Silicon, macOS 14+, Xcode 16+ (Swift 6), Node.js ≥ 22.

```sh
npm ci                                  # phụ thuộc engine
npm test                                # test engine/eval/scripts bằng node --test (không cần model)
(cd client && swift test)               # test client (VFlowCore + VFlowTests)
client/scripts/build-app.sh --no-model  # dựng client/build/VFlow.app, không kèm model
```

- Engine: **JavaScript ESM + JSDoc, không có bước build, không TypeScript, không framework.** Test bằng `node --test`.
- `client/scripts/build-app.sh --no-bundle` dựng nhanh khi phát triển (không đóng gói engine).
- Model chạy thật nằm ngoài repo (`~/.vflow/models/`, đã nằm trong `.gitignore`). Tải bằng `node bin/vflow.js models pull zipformer-vi-30m` — nhớ rằng model là **CC-BY-NC-ND-4.0** (xem [`NOTICE`](NOTICE)). **Không bao giờ commit model, tệp `.onnx`, âm thanh (`.wav`, `.pcm`) hay dữ liệu thật của bạn.**
- Khi thử app với dữ liệu riêng, đặt `VFLOW_HOME=/đường/dẫn/tạm` (và cổng khác bằng `VFLOW_PORT`) để không đụng `~/.vflow` thật của bạn.

### Xem giao diện mà không bật cửa sổ lên màn hình

Đừng chụp màn hình thật để kiểm giao diện (có thể lộ nội dung riêng của bạn hoặc của người khác). Dùng công cụ vẽ **ngoài màn hình**:

```sh
client/scripts/snapshot.sh /tmp/vflow-snapshots   # sáng + tối, nhiều mục, dữ liệu mẫu cô lập; không hiện cửa sổ
```

Mở các ảnh PNG trong thư mục đó để xem. Đã biết: ảnh vẽ ngoài màn hình có thể vẽ **sai** vật liệu kính mờ và danh sách (nền trắng) — đừng kết luận "lỗi giao diện" chỉ từ chỗ đó. Chi tiết và giới hạn: [`client/README.md`](client/README.md).

## Quy ước mã

- **Tiếng Việt** cho chú thích, thông điệp lỗi và chuỗi giao diện người dùng; **tên biến/hàm/tệp bằng tiếng Anh**.
- Engine: ESM + JSDoc; không thêm thư viện nếu không thật cần (hiện chỉ có `sherpa-onnx-node`). Client: chỉ framework của Apple, không gói Swift bên thứ ba.
- **Truth-first:** lỗi hoặc thiếu dữ liệu phải hiện đúng là lỗi/"không xác định", không biến thành thành công giả hay số 0 (ví dụ chưa đủ dữ liệu ⇒ hiện "—", không hiện "0").
- **Riêng tư là bất biến:** âm thanh không ghi xuống đĩa trừ khi người dùng bật *Lưu âm thanh*; log không chứa văn bản giọng nói; không telemetry. Thay đổi chạm tới các điều này cần giải thích rõ trong PR và cập nhật [`contract/engine-api.md`](contract/engine-api.md).
- Giữ `.editorconfig` (UTF-8, LF, thụt 2 dấu cách).
- **Không commit bí mật:** khoá API, token, `rewrite.key`, nội dung `~/.vflow`, ảnh chụp/âm thanh có dữ liệu thật, đường dẫn cá nhân, tên máy nội bộ. Dữ liệu mẫu trong test/fixture phải là dữ liệu bịa.

## Yêu cầu test cho mỗi thay đổi hành vi

- Sửa lỗi ⇒ thêm test **đỏ trước khi sửa, xanh sau khi sửa** tái hiện lỗi đó.
- Tính năng/hành vi mới ⇒ test bắt hành vi quan sát được, giá trị biên, bất biến và đường lỗi.
- Không viết test chỉ lặp lại cách nối dây (wiring), kiểm văn bản mã nguồn, mock tự trả lời chính nó, hay "không ném lỗi" trần. Test phải bắt được lỗi thật mà người dùng sẽ gặp; thử phá nhánh tương ứng và xác nhận test đỏ.
- Test phải xác định (không phụ thuộc mạng, giờ hệ thống, `~/.vflow` thật), độc lập nhau, chạy được khi chưa tải model.
- Trước khi gửi PR: `npm test` và `cd client && swift test` đều xanh, kèm đầu ra thật trong mô tả PR.

## Gửi pull request

1. Fork, tạo nhánh từ `main`.
2. Một PR một mục đích, nhỏ và dễ đọc. Điền mẫu PR.
3. Đổi hành vi người dùng thấy ⇒ cập nhật `README.md`/`CHANGELOG.md` (mục `Chưa phát hành`) và `contract/` nếu đổi API.
4. Bạn đóng góp theo cùng giấy phép của dự án (**Apache-2.0**, điều 5 của giấy phép: đóng góp được gửi vào dự án mặc nhiên theo giấy phép này).

## Bảo mật

Lỗ hổng bảo mật: **đừng mở issue công khai** — xem [`SECURITY.md`](SECURITY.md).
