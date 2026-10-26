# vflow

Công cụ đọc chính tả giọng nói tiếng Việt **chạy trong máy**: giữ phím, nói, nhả phím, chữ hiện vào ô đang gõ (giống [Haynoi](https://github.com/sonpiaz/haynoi)), nhưng dùng model tiếng Việt chạy cục bộ, không đám mây, không đăng nhập, không hạn mức. Bước viết lại (tuỳ chọn) đi qua 9Router cục bộ.

Thiết kế: [`docs/specs/2026-10-26-vflow-design.md`](docs/specs/2026-10-26-vflow-design.md) · Hợp đồng: [`contract/`](contract/).

## Cấu trúc thư mục (dự kiến)

```
engine/stt/     nhận dạng giọng nói (sherpa-onnx zipformer-vi; STT từ xa)
engine/post/    từ điển cá nhân, làm sạch, chế độ, viết lại qua 9Router
engine/server/  HTTP cục bộ 127.0.0.1 theo contract/engine-api.md
eval/           đo WER/CER/RTF/RAM, câu thoại mẫu, so sánh model
scripts/        công cụ phát triển (hp.sh: đồng bộ + chạy trên HP)
docs/           đặc tả thiết kế
contract/       hợp đồng API giữa các phần
```

JavaScript ESM + JSDoc, Node ≥ 22, test bằng `node --test`, không có bước build.

## Chạy test

Trên Mac:

```sh
npm test
```

`npm test` chạy mọi tệp `*.test.js` / `*.test.mjs` trong `engine/`, `eval/`, `scripts/`; chưa có test thì thoát 0, có test đỏ thì thoát khác 0.

Trên HP Windows (máy dựng/kiểm thử, qua `ssh windows-host`):

```sh
scripts/hp.sh status          # tên máy, node, RAM trống, ổ C:, python/ffmpeg
scripts/hp.sh sync            # mirror repo -> C:\Users\example\dev\vflow
scripts/hp.sh install         # npm install trên HP
scripts/hp.sh test            # npm test trên HP, trả đúng mã thoát
scripts/hp.sh run node -v     # chạy lệnh bất kỳ trong thư mục repo trên HP
scripts/hp.sh bench <lệnh…>   # như run, kèm RAM trống trước/sau và thời gian
```

- `sync` bỏ qua `.git`, `node_modules`, `models`, `.vflow`, `.DS_Store`, `.env`/`.env.*` và `*.wav` > 5 MB; xoá trên HP các tệp đã xoá trên Mac nhưng giữ nguyên `node_modules`, `models` trên HP; chỉ gửi tệp đổi nội dung (so SHA-256).
- `run`/`bench`/`install`/`test` chạy ở mức ưu tiên BelowNormal, đặt `NODE_OPTIONS=--max-old-space-size=1536`, và từ chối chạy (mã 3) nếu HP còn dưới 1500 MB RAM trống, trừ khi thêm `--force`. Ngưỡng đổi được bằng `VFLOW_HP_MIN_FREE_MB`.
- Lỗi SSH trả mã 255 kèm thông báo. Lệnh chạy qua `cmd.exe /c`, mỗi tham số được bọc ngoặc theo quy tắc Windows; tham số chứa `"` bị từ chối (mã 2), còn `%TÊN%` vẫn bị cmd.exe mở rộng.

## Nguyên tắc

- **Âm thanh người dùng không ghi xuống đĩa**; log không chứa văn bản giọng nói.
- **Không có secret trong repo** (khoá 9Router, token…): chỉ đọc từ biến môi trường hoặc tệp ngoài repo (`~/.vflow/`), không ghi vào log, fixture hay báo cáo.
- Truth-first: lỗi hoặc thiếu dữ liệu hiện đúng là lỗi / "không xác định", không biến thành thành công giả.
