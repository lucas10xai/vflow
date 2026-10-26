# Kiểm tay client macOS vflow

Dành cho chủ dự án, trên Mac thật. Mỗi bước có **Dự kiến**; khác dự kiến thì ghi lại bước + thông điệp trên thanh/menu.
Chuẩn bị: `client/scripts/build-app.sh`; model `zipformer-vi-30m` đã có trong `~/.vflow/models`; chưa có engine nào chạy (`lsof -nP -iTCP:7611 -sTCP:LISTEN` rỗng).

## A. Khởi động, cửa sổ "vflow" và cấp quyền
1. `open client/build/VFlow.app`.
   **Dự kiến:** không có biểu tượng Dock; biểu tượng micro trên menu bar (có thể bị ẩn nếu thanh menu chật/notch che — xem bước 1b); **cửa sổ "vflow" tự hiện** (mặc định bật) với: dòng hướng dẫn giữ ⌥ trái, trạng thái engine + model, 3 quyền (Chưa cấp lúc đầu), chế độ, lỗi gần nhất nếu có; hộp thoại xin quyền Micro (chữ tiếng Việt từ Info.plist); hộp thoại/nhắc “Theo dõi đầu vào”; cửa sổ hiện lỗi “Thiếu quyền Theo dõi đầu vào (Input Monitoring)”.
1b. Thu nhỏ cửa sổ "vflow" lại (đừng thoát app), giả lập biểu tượng thanh menu bị ẩn (thử thu nhỏ cửa sổ trình duyệt/mở nhiều ứng dụng để thanh menu chật). Chạy lại `open client/build/VFlow.app`.
   **Dự kiến:** KHÔNG có tiến trình VFlow thứ hai (`pgrep -fl "VFlow.app/Contents/MacOS/VFlow"` chỉ ra đúng 1 dòng); cửa sổ "vflow" được đưa ra trước thay vì mở lại từ đầu.
2. Bấm “Cho phép” Micro.
3. Trong cửa sổ "vflow" › hàng “Theo dõi đầu vào (Input Monitoring)” bấm “Cấp quyền…”.
   **Dự kiến:** mở đúng trang Quyền riêng tư & Bảo mật › Theo dõi đầu vào, có `vflow`. Bật lên.
   **Dự kiến:** trong ~2 s (cửa sổ tự kiểm lại quyền mỗi 2 giây khi đang hiện) hàng đó đổi thành “Đã cấp” màu xanh (nếu không: thoát và mở lại vflow). Menu cũng hết dòng “Thiếu quyền Theo dõi đầu vào…” cùng lúc.
4. Tương tự với “Trợ năng (Accessibility)”.
   **Dự kiến:** cả 3 quyền trong cửa sổ đều “Đã cấp”; menu không còn dòng “Thiếu quyền …”.
5. `curl -s 127.0.0.1:7611/healthz` và `pgrep -fl "vflow.js serve"`.
   **Dự kiến:** `ok:true`, `zipformer-vi-30m` `loaded:true` (sau vài giây); có một tiến trình node là con của VFlow. Cửa sổ "vflow" và menu đều nói “engine con v0.1.0, sẵn sàng” (không bao giờ khác nhau); mục Engine trong cửa sổ liệt kê từng model, model chưa tải có lý do (`not_downloaded`, `missing_token`…).
5b. Đóng cửa sổ "vflow" bằng nút đóng (không phải nút Thoát).
   **Dự kiến:** app vẫn chạy (`pgrep -fl "VFlow.app/Contents/MacOS/VFlow"` còn); engine con vẫn sống. Menu › “Mở cửa sổ vflow” (mục đầu menu) đưa cửa sổ lại.
5c. (Chỉ nếu có cài [Haynoi](https://github.com/sonpiaz/haynoi) hoặc ứng dụng đọc chính tả khác cùng danh sách xung đột) Mở Haynoi, rồi mở lại cửa sổ "vflow".
   **Dự kiến:** cửa sổ (và menu) hiện cảnh báo đỏ “Haynoi đang chạy: cả hai sẽ phản ứng khi giữ ⌥ trái. Hãy thoát một trong hai.”; vflow không tự thoát Haynoi. Thoát Haynoi ⇒ trong ~2 s cảnh báo biến mất.

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
14. Menu › Chế độ › “Thư (viết lại)” (hoặc chọn trong cửa sổ "vflow", mục Chế độ — hai nơi dùng chung UserDefaults), mở Mail/Notes, đọc một đoạn thư.
    **Dự kiến:** nếu 9Router + `rewrite.model` đã cấu hình: chữ được viết lại thành thư. Nếu chưa: vẫn dán bản chưa viết lại và thanh “Lỗi: Viết lại thư lỗi (no_model|no_key|…), đã dán bản chưa viết lại”. Thoát rồi mở lại app: chế độ vẫn là “Thư” (ở cả menu lẫn cửa sổ). Đặt lại “Tự động”.

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
23b. VoiceOver vẫn bật: mở cửa sổ "vflow", dùng Tab/VoiceOver để duyệt qua từng hàng quyền, nút “Cấp quyền…”, Picker chế độ, các nút thao tác — không dùng chuột.
    **Dự kiến:** mọi điều khiển đọc được tên + trạng thái bằng VoiceOver và bấm được bằng bàn phím (Space/Return); không có phần tử “mồ côi” không tên.
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
