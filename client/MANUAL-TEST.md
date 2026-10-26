# Kiểm tay client macOS vflow

Dành cho chủ dự án, trên Mac thật. Mỗi bước có **Dự kiến**; khác dự kiến thì ghi lại bước + thông điệp trên thanh/menu.
Chuẩn bị: `client/scripts/build-app.sh`; model `zipformer-vi-30m` đã có trong `~/.vflow/models`; chưa có engine nào chạy (`lsof -nP -iTCP:7611 -sTCP:LISTEN` rỗng).

## A. Khởi động và cấp quyền
1. `open client/build/VFlow.app`.
   **Dự kiến:** không có cửa sổ/biểu tượng Dock; biểu tượng micro trên menu bar; hộp thoại xin quyền Micro (chữ tiếng Việt từ Info.plist); hộp thoại/nhắc “Theo dõi đầu vào”; thanh đáy màn hình “Lỗi: Thiếu quyền Theo dõi đầu vào (Input Monitoring)”.
2. Bấm “Cho phép” Micro.
3. Menu › “Thiếu quyền Theo dõi đầu vào — mở Cài đặt…”.
   **Dự kiến:** mở đúng trang Quyền riêng tư & Bảo mật › Theo dõi đầu vào, có `vflow`. Bật lên.
   **Dự kiến:** trong ~3 s dòng đó biến khỏi menu (nếu không: thoát và mở lại vflow).
4. Menu › “Thiếu quyền Trợ năng — mở Cài đặt…”. Bật `vflow`.
   **Dự kiến:** menu không còn dòng “Thiếu quyền …”. Menu › “Hướng dẫn cấp quyền…” hiện cả 3 quyền “ĐÃ CẤP”.
5. `curl -s 127.0.0.1:7611/healthz` và `pgrep -fl "vflow.js serve"`.
   **Dự kiến:** `ok:true`, `zipformer-vi-30m` `loaded:true` (sau vài giây); có một tiến trình node là con của VFlow. Menu dòng đầu: “engine con v0.1.0, sẵn sàng”; Model › liệt kê model, model chưa tải có lý do (`not_downloaded`, `missing_token`…).

## B. Đọc chính tả
6. Mở Terminal, bấm vào dòng lệnh. Giữ ⌥ trái, chờ thấy “Đang nghe” (thanh mức âm nhảy theo giọng), nói “kiểm tra trạng thái git rồi commit”, nhả.
   **Dự kiến:** “Đang dịch” rồi “Xong”; chữ xuất hiện ở dấu nhắc Terminal (không tự Enter). Clipboard sau đó vẫn là nội dung cũ (⌘V ở chỗ khác ra nội dung trước khi nói).
7. Lặp lại trong Notes, trong ô nhập của trình duyệt (Chrome/Brave), trong Claude Code/Orca.
   **Dự kiến:** chữ chèn đúng chỗ con trỏ ở mọi nơi.
8. Sao chép một ảnh (hoặc chữ có định dạng từ trang web), đọc chính tả một câu, rồi ⌘V vào Notes.
   **Dự kiến:** ảnh/chữ có định dạng ban đầu được dán (khôi phục đủ kiểu dữ liệu).
9. Chạm ⌥ trái thật nhanh (< 0,2 s) nhiều lần; gõ ⌥+e, ⌥← trong Terminal.
   **Dự kiến:** không có thanh “Đang nghe”, không bật micro (chấm cam không hiện), ký tự đặc biệt/di chuyển từ vẫn hoạt động.
10. Giữ ⌥ trái, khi “Đang nghe” thì bấm một phím chữ (hoặc ⌘, ⇧, ⌥ phải, hoặc bấm chuột).
    **Dự kiến:** “Đã huỷ”, không chèn gì; phím đó vẫn tác động vào ứng dụng như bình thường.
11. Giữ ⌥ trái mà không nói gì 2 s, nhả.
    **Dự kiến:** “Không nghe thấy gì”, không chèn gì, clipboard không đổi.
12. Giữ ⌥ trái hơn 120 s (nói hoặc im).
    **Dự kiến:** tự chuyển “Đang dịch” đúng lúc 120 s; nhả phím sau đó không gửi lần hai.
13. Trong lúc “Đang dịch”, giữ ⌥ trái lần nữa.
    **Dự kiến:** không có lần ghi thứ hai chồng lên.
14. Menu › Chế độ › “Thư (viết lại)”, mở Mail/Notes, đọc một đoạn thư.
    **Dự kiến:** nếu 9Router + `rewrite.model` đã cấu hình: chữ được viết lại thành thư. Nếu chưa: vẫn dán bản chưa viết lại và thanh “Lỗi: Viết lại thư lỗi (no_model|no_key|…), đã dán bản chưa viết lại”. Thoát rồi mở lại app: chế độ vẫn là “Thư”. Đặt lại “Tự động”.

## C. Lỗi và hồi phục
15. Rút micro USB/tai nghe giữa lúc đang nghe (nếu có micro ngoài).
    **Dự kiến:** “Lỗi: Micro không dùng được: thiết bị micro thay đổi hoặc bị rút”; lần giữ ⌥ sau dùng micro mặc định mới.
16. System Settings › Micro: tắt vflow, giữ ⌥.
    **Dự kiến:** “Lỗi: Chưa cấp quyền Micro”. Bật lại.
17. `pkill -9 -f "vflow.js serve"`.
    **Dự kiến:** sau ~1 s có engine con mới (`pgrep -fl "vflow.js serve"` pid khác); giữ ⌥ nói vẫn được (sau khi model tải xong).
18. Đổi tạm `~/.vflow/client.json` thành `{"node":"/khong/co/node"}`, thoát và mở lại app.
    **Dự kiến:** “Lỗi: Cấu hình client lỗi: "node" không chạy được: /khong/co/node”; không âm thầm dùng node khác. Xoá dòng đó, mở lại.
19. Thoát app, chạy tay `node bin/vflow.js serve` ở Terminal, mở app.
    **Dự kiến:** menu “dùng engine có sẵn”; không có node thứ hai. Thoát app ⇒ engine chạy tay vẫn sống. Tắt engine chạy tay (^C) khi app đang mở ⇒ trong ~5 s app tự chạy engine con.
20. Đọc chính tả khi engine đang khởi động lại/chưa tải model.
    **Dự kiến:** “Lỗi: Engine không chạy” hoặc “Lỗi: Model chưa sẵn sàng (…)”, không chèn gì. Menu › “Thử lại lần cuối” (sáng trong 5 phút) gửi lại đúng đoạn âm thanh đó khi engine đã sẵn sàng.
21. Đổi tạm nội dung `~/.vflow/token` (sao lưu trước!) khi app đang chạy với engine cũ, giữ ⌥ nói.
    **Dự kiến:** “Lỗi: Sai token engine (~/.vflow/token)”. Khôi phục token.
22. Tắt quyền Trợ năng, đọc chính tả.
    **Dự kiến:** “Lỗi: Không dán được (thiếu quyền Trợ năng); chữ đã nằm trong clipboard, bấm ⌘V”; ⌘V tay dán đúng chữ.

## D. Khác
23. Bật VoiceOver (⌘F5), đọc chính tả một câu.
    **Dự kiến:** VoiceOver đọc “vflow đang dịch giọng nói”, “vflow đã chèn chữ”; biểu tượng menu bar có nhãn.
24. Bật Giảm chuyển động (Trợ năng › Màn hình), giữ ⌥.
    **Dự kiến:** thanh mức âm đổi tức thì, không hoạt ảnh.
25. Ứng dụng toàn màn hình / Space khác: giữ ⌥.
    **Dự kiến:** thanh vẫn hiện ở đáy màn hình có con trỏ, không lấy focus (đang gõ vẫn gõ tiếp được).
26. Menu › “Bật khi đăng nhập”, đăng xuất/đăng nhập.
    **Dự kiến:** vflow tự mở; System Settings › Mục đăng nhập có vflow. Tắt lại nếu không muốn.
27. Menu › Thoát vflow; `pgrep -fl "vflow.js serve"`.
    **Dự kiến:** không còn engine con.
28. Sau khi chạy lại `build-app.sh`: mở app.
    **Dự kiến:** có thể phải cấp lại Theo dõi đầu vào/Trợ năng (chữ ký ad-hoc mới) — app báo rõ, không im lặng.
