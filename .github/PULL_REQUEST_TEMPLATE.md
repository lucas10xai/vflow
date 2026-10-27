## Thay đổi gì và vì sao

<!-- Một PR một mục đích. Liên kết issue nếu có: Closes #… -->

## Cách kiểm

<!-- Dán ĐẦU RA THẬT. Không ghi "đã chạy" nếu chưa chạy. -->

```
npm test
(cd client && swift test)
```

- [ ] `npm test` xanh
- [ ] `cd client && swift test` xanh
- [ ] Đổi hành vi ⇒ có test mới bắt đúng hành vi đó (đã thử phá nhánh và thấy test đỏ)
- [ ] Đổi giao diện ⇒ đã xem ảnh từ `client/scripts/snapshot.sh` (vẽ ngoài màn hình), ghi rõ nếu có chỗ vẽ ngoài màn hình có thể sai (kính mờ, danh sách)

## Riêng tư và bảo mật

- [ ] Không commit bí mật, token, khoá, âm thanh, `~/.vflow`, model (`.onnx`), đường dẫn hay tên máy cá nhân
- [ ] Âm thanh vẫn không ghi xuống đĩa khi *Lưu âm thanh* tắt; log không chứa văn bản giọng nói
- [ ] Không thêm gửi dữ liệu ra ngoài máy (hoặc đã nêu rõ ở trên và cập nhật `README.md`/`contract/`)

## Tài liệu

- [ ] Cập nhật `CHANGELOG.md` (mục *Chưa phát hành*) nếu người dùng thấy khác biệt
- [ ] Cập nhật `contract/engine-api.md` nếu đổi API engine
- [ ] Phụ thuộc mới ⇒ đã cập nhật `NOTICE` với đúng giấy phép (đã tự kiểm)

Bằng việc gửi PR, tôi đồng ý đóng góp của mình theo giấy phép Apache-2.0 của dự án.
