# Kiểm tay client macOS vflow

Dành cho chủ dự án, trên Mac thật. Mỗi bước có **Dự kiến**; khác dự kiến thì ghi lại bước + thông điệp trên thanh/menu.
Chuẩn bị: `client/scripts/build-app.sh`; model `zipformer-vi-30m` đã có trong `~/.vflow/models`; chưa có engine nào chạy (`lsof -nP -iTCP:7611 -sTCP:LISTEN` rỗng).

## A. Khởi động, Dock, cửa sổ "vflow" và cấp quyền
1. `open client/build/VFlow.app`.
   **Dự kiến:** **có biểu tượng Dock** (micro cam trên nền tối) và app xuất hiện trong ⌘-Tab; biểu tượng micro trên menu bar cũng có (phụ, có thể bị ẩn nếu thanh menu chật/notch che — xem bước 1b, tắt được ở Cài đặt); **cửa sổ chính "vflow" tự hiện** (mặc định bật) ở tab **Tổng quan** với: dòng hướng dẫn giữ ⌥ trái, trạng thái engine + model, 3 quyền (Chưa cấp lúc đầu), chế độ, lỗi gần nhất nếu có; thanh bên có đủ 4 mục Tổng quan/Lịch sử/Từ điển/Cài đặt; hộp thoại xin quyền Micro (chữ tiếng Việt từ Info.plist); hộp thoại/nhắc “Theo dõi đầu vào”; cửa sổ hiện lỗi “Thiếu quyền Theo dõi đầu vào (Input Monitoring)”. Menu ứng dụng ở góc trên trái có tên "vflow" với Giới thiệu/Cài đặt…(⌘,)/Ẩn(⌘H)/Thoát(⌘Q).
1a. Bấm menu "vflow" › "Cài đặt…" (hoặc ⌘,).
   **Dự kiến:** cửa sổ chuyển sang tab **Cài đặt** (không mở cửa sổ mới).
1b. Thu nhỏ cửa sổ "vflow" lại (đừng thoát app), giả lập biểu tượng thanh menu bị ẩn (thử thu nhỏ cửa sổ trình duyệt/mở nhiều ứng dụng để thanh menu chật). Bấm biểu tượng Dock của vflow (hoặc chạy lại `open client/build/VFlow.app`).
   **Dự kiến:** KHÔNG có tiến trình VFlow thứ hai (`pgrep -fl "VFlow.app/Contents/MacOS/VFlow"` chỉ ra đúng 1 dòng); cửa sổ "vflow" được đưa ra trước thay vì mở lại từ đầu.
2. Bấm “Cho phép” Micro.
3. Trong cửa sổ "vflow" › hàng “Theo dõi đầu vào (Input Monitoring)” bấm “Cấp quyền…”.
   **Dự kiến:** mở đúng trang Quyền riêng tư & Bảo mật › Theo dõi đầu vào, có `vflow`. Bật lên.
   **Dự kiến:** trong ~2 s (cửa sổ tự kiểm lại quyền mỗi 2 giây khi đang hiện) hàng đó đổi thành “Đã cấp” màu xanh (nếu không: thoát và mở lại vflow). Menu cũng hết dòng “Thiếu quyền Theo dõi đầu vào…” cùng lúc.
4. Tương tự với “Trợ năng (Accessibility)”.
   **Dự kiến:** cả 3 quyền trong cửa sổ đều “Đã cấp”; menu không còn dòng “Thiếu quyền …”.
5. `curl -s 127.0.0.1:7611/healthz` và `pgrep -fl "vflow.js serve"`.
   **Dự kiến:** `ok:true`, `zipformer-vi-30m` `loaded:true` (sau vài giây); có một tiến trình node là con của VFlow. Cửa sổ "vflow" và menu đều nói “engine con v0.1.0, sẵn sàng” (không bao giờ khác nhau); mục Engine trong cửa sổ liệt kê từng model, model chưa tải có lý do (`not_downloaded`, `missing_token`…).
5b. Đóng cửa sổ "vflow" bằng nút đóng đỏ (không phải ⌘Q/nút Thoát). Thử giữ ⌥ trái đọc chính tả một câu khi cửa sổ đang đóng.
   **Dự kiến:** app vẫn chạy (`pgrep -fl "VFlow.app/Contents/MacOS/VFlow"` còn, vẫn còn trong Dock/⌘-Tab); engine con vẫn sống; **phím nóng vẫn hoạt động bình thường** (chữ vẫn chèn được) — đóng cửa sổ không tắt tính năng chính. Menu › “Mở cửa sổ vflow” (mục đầu menu), bấm biểu tượng Dock, hoặc `open client/build/VFlow.app` đều đưa cửa sổ lại (giữ nguyên tab đang chọn lúc đóng).
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

## D. Lịch sử và Từ điển
D1. Mở tab "Lịch sử", đọc chính tả vài câu ở Terminal.
    **Dự kiến:** mỗi câu (không rỗng, không "Không nghe thấy gì") xuất hiện ở đầu danh sách sau khi chèn xong — mới nhất trên cùng, kèm giờ, bundle id ứng dụng đích, chế độ, model. "Sao chép" đưa đúng văn bản vào clipboard. Gõ vào ô tìm kiếm lọc đúng theo nội dung.
D2. Bấm "Sửa…" ở một mục, sửa vài chữ rồi "Lưu".
    **Dự kiến:** gọi `/v1/corrections`; nếu engine nhận ra thuật ngữ đổi (vd. "đi plôi" → "deploy") thì hiện gợi ý "Thêm '<term>' ← '<spoken>'?"; bấm "Thêm" mới ghi vào từ điển (xem lại ở tab Từ điển, mục đó có biến thể mới); KHÔNG tự dán văn bản đã sửa vào Terminal hay ứng dụng nào. Sửa câu mà không đổi gì đáng kể (chỉ khác hoa/thường) ⇒ "Không có gợi ý".
D3. Xoá một mục lịch sử; rồi "Xoá toàn bộ lịch sử…" và xác nhận.
    **Dự kiến:** mục biến mất ngay; xoá toàn bộ cần xác nhận trước, sau đó danh sách trống hẳn ("Chưa có câu nào trong lịch sử.").
D4. Tab Cài đặt › tắt "Lưu lịch sử", đọc chính tả một câu, bật lại.
    **Dự kiến:** lúc tắt, câu mới KHÔNG xuất hiện ở tab Lịch sử (và `~/.vflow/history.jsonl` không có dòng mới — kiểm bằng `wc -l`); lịch sử cũ vẫn còn nguyên, không bị xoá chỉ vì tắt công tắc.
D5. Mở tab "Từ điển", bấm "Thêm mục…", nhập thuật ngữ + vài cách nói (mỗi dòng một cách), Lưu.
    **Dự kiến:** mục mới xuất hiện trong danh sách, số lần dùng 0. Thử Lưu với thuật ngữ trùng mục có sẵn ⇒ báo lỗi tiếng Việt rõ ràng (không đè, không nuốt lỗi). Sửa một mục (đổi cách nói), Xoá một mục (có xác nhận) — số mục cập nhật đúng ngay.
D6. Tắt engine (Tổng quan › "Khởi động lại engine" trong lúc đang tắt, hoặc `pkill -9 -f "vflow.js serve"` rồi nhanh tay mở tab Từ điển trước khi engine con tự khởi động lại), mở tab "Từ điển".
    **Dự kiến:** hiện rõ chữ đỏ "Không kết nối được engine: …" — KHÔNG hiện danh sách trống như thể từ điển thật sự rỗng.

## E. Khác
23. Bật VoiceOver (⌘F5), đọc chính tả một câu.
    **Dự kiến:** VoiceOver đọc “vflow đang dịch giọng nói”, “vflow đã chèn chữ”; biểu tượng menu bar có nhãn.
23b. VoiceOver vẫn bật: mở cửa sổ "vflow", dùng Tab/VoiceOver để duyệt qua thanh bên 4 tab, từng hàng quyền, nút “Cấp quyền…”, Picker chế độ, các nút thao tác ở Lịch sử/Từ điển/Cài đặt — không dùng chuột.
    **Dự kiến:** mọi điều khiển đọc được tên + trạng thái bằng VoiceOver và bấm được bằng bàn phím (Space/Return, mũi tên để đổi tab); không có phần tử “mồ côi” không tên.
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
