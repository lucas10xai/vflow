# Kiểm tay client macOS vflow

Dành cho chủ dự án, trên Mac thật. Mỗi bước có **Dự kiến**; khác dự kiến thì ghi lại bước + thông điệp trên thanh/menu.
Chuẩn bị: `client/scripts/build-app.sh`; model `zipformer-vi-30m` đã có trong `~/.vflow/models`; chưa có engine nào chạy (`lsof -nP -iTCP:7611 -sTCP:LISTEN` rỗng).

## A. Khởi động, Dock, cửa sổ "vflow", Chào mừng và cấp quyền
1. `open client/build/VFlow.app` (lần đầu, chưa cấp quyền nào).
   **Dự kiến:** **có biểu tượng Dock** (ô cam bo góc, chữ V đen) và app xuất hiện trong ⌘-Tab; biểu tượng TRẮNG trên thanh menu tối (đen trên thanh menu sáng — đổi System Settings › Chung › Giao diện để thử cả hai), phụ, có thể bị ẩn nếu thanh menu chật/notch che (xem bước 1b, tắt được ở Cài đặt › Chung); **tờ "Chào mừng đến với vflow" tự hiện** (chưa đủ quyền) với 3 bước Micro/Theo dõi đầu vào/Trợ năng, mỗi bước có nút "Mở Cài đặt hệ thống" và dấu tích tự cập nhật; **cửa sổ chính "vflow" cũng tự hiện** (mặc định bật) ở mục **Tổng quan**: thẻ trạng thái lớn "Thiếu 3 quyền macOS" + nút "Cấp quyền…", thẻ Phím tắt, thẻ Chế độ (6 chế độ, nhãn "Trong máy"/"Gửi chữ qua 9Router"), thẻ Quyền (0/3), thẻ "Hôm nay"; thanh bên có logo+"vflow" rồi 2 nhóm — **Sử dụng** (Tổng quan có huy hiệu cam "3", Lịch sử) và **Cá nhân hoá** (Từ điển, Snippets) — KHÔNG có mục Cài đặt trong thanh bên; hộp thoại xin quyền Micro (chữ tiếng Việt từ Info.plist); hộp thoại/nhắc "Theo dõi đầu vào"; thẻ lỗi gần nhất "Thiếu quyền Theo dõi đầu vào (Input Monitoring)" (đóng được bằng nút x). Menu ứng dụng ở góc trên trái có tên "vflow" với Giới thiệu/Cài đặt…(⌘,)/Ẩn(⌘H)/Thoát(⌘Q); menu "Trợ giúp" có thêm "Xem hướng dẫn chào mừng…" (mở lại tờ Chào mừng bất cứ lúc nào).
1a. Bấm menu "vflow" › "Cài đặt…" (hoặc ⌘,).
   **Dự kiến:** mở một **CỬA SỔ RIÊNG** "Cài đặt vflow" (không phải chuyển mục trong cửa sổ chính) với thanh công cụ 4 mục: Chung/Đám mây/Lịch sử & riêng tư/Nâng cao. Bấm lại ⌘, lần nữa (hoặc menu Cài đặt… lần nữa) ⇒ KHÔNG mở cửa sổ Cài đặt thứ hai, chỉ đưa cửa sổ đã có ra trước. Thử phím ⌘1…⌘4 ở cửa sổ CHÍNH (không phải cửa sổ Cài đặt) ⇒ chuyển lần lượt Tổng quan/Lịch sử/Từ điển/Snippets.
1a2. Bấm "Bắt đầu dùng vflow" ở tờ Chào mừng (dù chưa cấp đủ quyền).
   **Dự kiến:** tờ Chào mừng đóng lại ngay (không chặn), cửa sổ chính và menu vẫn hoạt động bình thường. Mở lại qua menu "Trợ giúp › Xem hướng dẫn chào mừng…" ⇒ hiện lại đúng 3 bước với trạng thái quyền hiện tại.
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
D4. Cài đặt › Lịch sử & riêng tư › tắt "Lưu lịch sử", đọc chính tả một câu, bật lại.
    **Dự kiến:** lúc tắt, câu mới KHÔNG xuất hiện ở tab Lịch sử (và `~/.vflow/history.jsonl` không có dòng mới — kiểm bằng `wc -l`); lịch sử cũ vẫn còn nguyên, không bị xoá chỉ vì tắt công tắc.
D5. Mở tab "Từ điển", bấm "Thêm mục…", nhập thuật ngữ + vài cách nói (mỗi dòng một cách), Lưu.
    **Dự kiến:** mục mới xuất hiện trong danh sách, số lần dùng 0. Thử Lưu với thuật ngữ trùng mục có sẵn ⇒ báo lỗi tiếng Việt rõ ràng (không đè, không nuốt lỗi). Sửa một mục (đổi cách nói), Xoá một mục (có xác nhận) — số mục cập nhật đúng ngay.
D6. (M4b) `pkill -9 -f "vflow.js serve"` rồi NHANH TAY mở tab "Từ điển" trong lúc engine con đang tự khởi động lại (vài trăm ms tới vài giây).
    **Dự kiến:** chữ xám "Đang chờ engine khởi động…" (KHÔNG phải lỗi đỏ, vì engine đang tự hồi phục) — danh sách tự tải lại (không cần bấm gì) ngay khi engine lên lại, không treo mãi ở "Đang chờ". Mở lại tab sau khi engine đã sẵn sàng ⇒ vào thẳng danh sách, không thấy "Đang chờ" nữa.
D6b. Làm engine bỏ cuộc hẳn: `pkill -9 -f "vflow.js serve"` liên tục (≥ 5 lần trong 60 giây, xem README mục Engine) rồi mở tab "Từ điển".
    **Dự kiến:** hiện rõ chữ đỏ "Không kết nối được engine: …" kèm nút "Thử lại" và "Khởi động lại engine" — KHÔNG hiện danh sách trống như thể từ điển thật sự rỗng, KHÔNG còn chữ "Đang chờ" (engine sẽ không tự lên nữa).

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

## F. Đóng gói tự đủ & cài đặt (M4b)
29. `client/scripts/build-app.sh` xong, rồi `VFLOW_HOME=/tmp/vflow-selftest ./client/build/VFlow.app/Contents/MacOS/VFlow` (thư mục trống, chưa có model) với `client.json` chỉ có `{"port": <cổng riêng>}`.
    **Dự kiến:** tab Tổng quan hiện "Đang chuẩn bị model lần đầu…" rồi tự hết (không lỗi); `/tmp/vflow-selftest/models/zipformer-vi-30m/` xuất hiện đủ tệp, sha256 khớp `~/.vflow/models/zipformer-vi-30m`; engine lên với model `loaded:true` dù máy không có Node/npm cài sẵn.
30. Lặp lại bước 29 lần nữa (model đã có ở `/tmp/vflow-selftest`).
    **Dự kiến:** KHÔNG chép lại, không có dòng "Đang chuẩn bị model" (hoặc hiện rồi biến mất ngay vì `.alreadyPresent`); thời gian mtime của tệp model không đổi.
31. `client/scripts/install-app.sh`.
    **Dự kiến:** thoát nhẹ nhàng bản vflow cũ đang chạy (nếu đường dẫn thực thi thuộc `client/build/` hoặc `/Applications/vflow.app`) — KHÔNG đụng Haynoi hay app khác; `/Applications/vflow.app` xuất hiện; `codesign --verify --deep --strict /Applications/vflow.app` OK. Mở `/Applications/vflow.app` lần đầu ⇒ macOS đòi cấp lại quyền macOS (chữ ký ad-hoc khác bản cũ) — trừ khi đã chạy `make-signing-identity.sh --yes` trước (xem mục H).
32. `client/scripts/uninstall-app.sh`.
    **Dự kiến:** thoát vflow đang chạy từ `/Applications/vflow.app` rồi xoá; `~/.vflow` (token, từ điển, lịch sử) KHÔNG bị đụng — kiểm bằng `ls ~/.vflow`.

## G. Hands-free, Esc, Command Mode, Enter bằng giọng, Snippets, Cài đặt đám mây
33. Đúp ⌥ trái thật nhanh (hai lần chạm < 0,2 s mỗi lần, cách nhau ≤ 0,35 s), bỏ tay ra khỏi phím.
    **Dự kiến:** thanh trạng thái "Đang nghe (đã khoá, bấm ⌥ để xong, Esc để huỷ)"; thanh mức âm vẫn nhảy theo giọng dù không giữ phím. Nói một câu, rồi bấm ⌥ một lần (nhấn thả nhanh).
    **Dự kiến:** "Đang dịch" rồi "Xong"; chữ chèn đúng chỗ, giống ghi kiểu giữ phím.
34. Lặp lại đúp ⌥ để vào ghi khoá, lần này bấm **Esc** thay vì bấm lại ⌥.
    **Dự kiến:** "Đã huỷ" ngay lập tức, không chèn gì, không gửi âm thanh. Gõ thử Esc ở một ô văn bản khác (vd. Spotlight) ngay sau đó để chắc Esc không bị "nuốt" mất lần đó — phải đóng Spotlight bình thường.
35. Giữ ⌥ trái (kiểu giữ phím) đang "Đang nghe", bấm **Esc**.
    **Dự kiến:** "Đã huỷ"; vẫn đang giữ ⌥ thì chưa ghi lại tới khi nhả rồi bấm lại.
36. Mở **Notes**, bôi đen một đoạn văn bản có sẵn. Giữ ⌥ trái; trong 400 ms đầu bấm thêm **⌃ trái** (vẫn giữ cả hai), nói một lệnh sửa (vd. "viết hoa toàn bộ"), nhả cả hai phím.
    **Dự kiến:** thanh trạng thái chuyển "Đang nghe lệnh" ngay khi bấm ⌃; sau khi nhả ⇒ "Đang dịch" rồi "Xong"; đoạn bôi đen được THAY bằng kết quả (không còn lời dẫn, không có "Lệnh:"); nếu chưa đặt model 9Router (Cài đặt) thì thay vào đó hiện lỗi "Chế độ đám mây đang tắt…"/"Không thể xử lý lệnh…" và đoạn bôi đen giữ NGUYÊN (không bị xoá/thay bằng gì).
37. Lặp lại bước 36 nhưng KHÔNG bôi đen gì trước (chỉ đặt con trỏ vào ô trống), nói "soạn một câu chào buổi sáng ngắn gọn".
    **Dự kiến:** câu mới được dán vào đúng vị trí con trỏ (chế độ "soạn mới" — `draft`, không có đoạn chọn để thay).
38. Mở **Terminal**, gõ vài chữ rồi bôi đen bằng chuột (Terminal thường KHÔNG hỗ trợ Accessibility `kAXSelectedTextAttribute`). Giữ ⌥+⌃ như bước 36, nói một lệnh sửa đoạn đó.
    **Dự kiến:** vẫn lấy được đoạn đang bôi đen (qua đường ⌘C tổng hợp dự phòng, chậm hơn một chút); sau khi xong, thử ⌘V ở một chỗ khác để xác nhận clipboard GỐC (trước khi vflow mượn tạm) đã được khôi phục đúng, không phải đoạn vừa bôi đen trong Terminal.
39. Tab **Lịch sử**: tìm mục vừa tạo ở bước 36/37.
    **Dự kiến:** có một dòng kiểu lệnh (`mode` bắt đầu bằng "command:"), `text_raw` là câu LỆNH đã nói, `text` là KẾT QUẢ — **không có bất kỳ dòng nào chứa đoạn văn bản đã bôi đen** ở Notes/Terminal.
40. Mở cửa sổ **Cài đặt** (⌘,) › mục **Đám mây**: tắt công tắc "Cho phép gửi chữ qua 9Router".
    **Dự kiến:** đổi ngay (không cần Lưu riêng). Thử chế độ Gọn hoặc Command Mode (bước 36) lúc này.
    **Dự kiến:** không có yêu cầu mạng nào tới 9Router; Gọn vẫn dán được bản đã qua từ điển + làm sạch bằng quy tắc, kèm lỗi "Chế độ đám mây đang tắt…"; Command Mode báo lỗi rõ, không dán gì. Bật lại công tắc.
41. Cài đặt › Đám mây › xoá trắng ô "Model", bấm Lưu.
    **Dự kiến:** dòng cảnh báo cam "Chưa đặt model: Gọn/Thư/Command Mode sẽ không chạy được." hiện ra. Thử chế độ Gọn ⇒ lỗi rõ ràng (không phải "không rõ lý do"). Đặt lại tên model cũ.
42. Cài đặt › Đám mây › đổi "Thời gian chờ (giây)" xuống 1, mục Model đặt một model KHÔNG tồn tại trên 9Router thật.
    **Dự kiến:** chế độ Gọn/Thư/Command Mode báo lỗi "quá thời gian" hoặc lỗi dịch vụ rõ ràng trong khoảng 1 giây, không treo lâu. Đặt lại 8 giây.
43. Mở **Terminal**, chọn chế độ **Lập trình** (menu hoặc tab Tổng quan), giữ ⌥ nói "biến tên gạch dưới người dùng mới bằng mười, rồi nhấn enter". Trước đó, Cài đặt bật "Nhấn Enter bằng giọng".
    **Dự kiến:** chữ chèn vào Terminal là `biến tên_người_dùng_mới bằng mười` (không còn cụm "nhấn enter" trong chữ chèn) — RỒI dòng lệnh đó tự chạy (phím Return được gửi ~150 ms sau khi dán). Tắt công tắc "Nhấn Enter bằng giọng" ở Cài đặt rồi lặp lại câu tương tự.
    **Dự kiến:** chữ vẫn chèn đúng nhưng Return KHÔNG được gửi — con trỏ nằm cuối dòng lệnh, chưa chạy, phải tự bấm Enter.
44. Tab **Snippets** › "Thêm mục…", trigger "chữ ký email", nội dung nhiều dòng (vd. "Trân trọng,\nAn"), Lưu.
    **Dự kiến:** mục mới xuất hiện, số lần dùng 0. Mở Notes, giữ ⌥ nói đúng "chữ ký email" (cả câu, không thêm gì khác), nhả.
    **Dự kiến:** nội dung nhiều dòng đã lưu được chèn NGUYÊN VĂN (không qua từ điển/làm sạch). Thử nói "chèn chữ ký email vào cuối thư" (cụm "chèn <trigger>" ở giữa câu).
    **Dự kiến:** phần "chữ ký email" trong câu được thay bằng nội dung đã lưu, phần còn lại của câu giữ nguyên. Quay lại tab Snippets, số lần dùng đã tăng.
45. Tab Snippets › thêm trigger trùng (sau khi bỏ dấu/hoa thường/dấu câu) với một trigger có sẵn.
    **Dự kiến:** báo lỗi tiếng Việt rõ ràng ("trùng với một mục khác…"), không lưu, không đè mục cũ.

## H. Chữ ký ổn định (chạy MỘT LẦN, cần chủ dự án tự duyệt)
46. `client/scripts/make-signing-identity.sh --dry-run` trước để xem các lệnh sẽ chạy (không đổi gì).
    **Dự kiến:** in ra 4 lệnh (`openssl req`, `openssl pkcs12`, `security import`, `security set-key-partition-list`), không hỏi mật khẩu, không tạo gì trong keychain.
47. `client/scripts/make-signing-identity.sh --yes`.
    **Dự kiến:** 1–2 hộp thoại hệ thống hỏi mật khẩu/Touch ID (Keychain Access) — xác nhận cho phép `codesign`/`security` dùng khoá riêng mới. Xong, `security find-identity -v -p codesigning | grep vflow` ra đúng 1 dòng "vflow Local Signing". Chạy lại script lần nữa (không cờ khác) ⇒ in "Đã có … — không làm gì thêm" rồi thoát ngay, không hỏi mật khẩu lần nữa.
48. `client/scripts/build-app.sh`.
    **Dự kiến:** dòng "ký ổn định bằng "vflow Local Signing": quyền macOS được giữ qua các lần cài" thay vì cảnh báo ad-hoc. `codesign -dvvv client/build/VFlow.app | grep Authority` ra `Authority=vflow Local Signing`.
49. Mở app đã ký ổn định lần đầu, cấp đủ 3 quyền macOS. Xoá `client/build/VFlow.app`, chạy lại `build-app.sh`, mở lại.
    **Dự kiến:** KHÔNG bị đòi cấp lại quyền (khác hẳn bản ad-hoc ở bước 28/31) — vì chữ ký (danh tính) giống hệt lần trước dù nhị phân có thể đổi byte.
