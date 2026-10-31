# Kiểm tay client macOS vflow

Dành cho chủ dự án, trên Mac thật. Mỗi bước có **Dự kiến**; khác dự kiến thì ghi lại bước + thông điệp trên thanh/menu.
Chuẩn bị: `client/scripts/build-app.sh`; model `zipformer-vi-30m` đã có trong `~/.vflow/models`; chưa có engine nào chạy (`lsof -nP -iTCP:7611 -sTCP:LISTEN` rỗng).

## A. Khởi động, Dock, cửa sổ "vflow", Chào mừng và cấp quyền
1. `open client/build/VFlow.app` (lần đầu, chưa cấp quyền nào).
   **Dự kiến:** **có biểu tượng Dock** (ô cam bo góc, chữ V đen) và app xuất hiện trong ⌘-Tab; biểu tượng TRẮNG trên thanh menu tối (đen trên thanh menu sáng — đổi System Settings › Chung › Giao diện để thử cả hai), phụ, có thể bị ẩn nếu thanh menu chật/notch che (xem bước 1b, tắt được ở Cài đặt › Chung); **tờ "Chào mừng đến với vflow" tự hiện** (chưa đủ quyền) với 3 bước Micro/Theo dõi đầu vào/Trợ năng, mỗi bước có nút "Mở Cài đặt hệ thống" và dấu tích tự cập nhật; **cửa sổ chính "vflow" cũng tự hiện** (mặc định bật) ở mục **Tổng quan**: thẻ trạng thái lớn "Thiếu 3 quyền macOS" + nút "Cấp quyền…", thẻ Phím tắt, thẻ Chế độ (6 chế độ, nhãn "Trong máy"/"Gửi chữ qua 9Router"), thẻ Quyền (0/3), thẻ "Hôm nay"; thanh bên có logo+"vflow" rồi 2 nhóm — **Sử dụng** (Tổng quan có huy hiệu cam "3", Thống kê, Lịch sử) và **Cá nhân hoá** (Từ điển, Snippets) — KHÔNG có mục Cài đặt trong thanh bên; hộp thoại xin quyền Micro (chữ tiếng Việt từ Info.plist); hộp thoại/nhắc "Theo dõi đầu vào"; thẻ lỗi gần nhất "Thiếu quyền Theo dõi đầu vào (Input Monitoring)" (đóng được bằng nút x). Menu ứng dụng ở góc trên trái có tên "vflow" với Giới thiệu/Cài đặt…(⌘,)/Ẩn(⌘H)/Thoát(⌘Q); menu "Trợ giúp" có thêm "Xem hướng dẫn chào mừng…" (mở lại tờ Chào mừng bất cứ lúc nào).
1a. Bấm menu "vflow" › "Cài đặt…" (hoặc ⌘,).
   **Dự kiến:** mở một **CỬA SỔ RIÊNG** "Cài đặt vflow" (không phải chuyển mục trong cửa sổ chính) với thanh công cụ 8 mục: Chung/Giọng nói/Ứng dụng/Đám mây/Dữ liệu/Phím tắt/Lịch sử & riêng tư/Nâng cao (V2 thêm Giọng nói/Ứng dụng/Dữ liệu). Bấm lại ⌘, lần nữa (hoặc menu Cài đặt… lần nữa) ⇒ KHÔNG mở cửa sổ Cài đặt thứ hai, chỉ đưa cửa sổ đã có ra trước. Thử phím ⌘1…⌘5 ở cửa sổ CHÍNH (không phải cửa sổ Cài đặt) ⇒ chuyển lần lượt Tổng quan/Thống kê/Lịch sử/Từ điển/Snippets.
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
    **Dự kiến (Q2):** KHÔNG còn thanh đỏ "thiết bị micro thay đổi hoặc bị rút" khi đầu vào vẫn dùng được; vflow dựng lại êm và ghi tiếp bằng micro còn lại (HUD nhắc nhẹ MỘT lần nếu micro đã chọn không còn); chỉ khi không thu được chút âm thanh nào mới báo đỏ với thông điệp đúng nguyên nhân. Xem mục M.
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
D4. Cài đặt › Dữ liệu & Riêng tư › tắt "Lưu lịch sử", đọc chính tả một câu, bật lại.
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
41. Cài đặt › Nâng cao › xoá trắng ô "Model", bấm Lưu.
    **Dự kiến:** dòng cảnh báo cam "Chưa đặt model: Gọn/Thư/Command Mode sẽ không chạy được." hiện ra. Thử chế độ Gọn ⇒ lỗi rõ ràng (không phải "không rõ lý do"). Đặt lại tên model cũ.
42. Cài đặt › Nâng cao › đổi "Thời gian chờ (giây)" xuống 1, mục Model đặt một model KHÔNG tồn tại trên 9Router thật.
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

## I. U2: Tổng quan/khung chính, Lịch sử/Từ điển/Snippets, HUD, cô lập UserDefaults
50. `VFLOW_HOME=/tmp/vflow-u2-test1 ./client/build/VFlow.app/Contents/MacOS/VFlow --open-tab tongquan` (thư mục trống, lần đầu).
    **Dự kiến:** cửa sổ mặc định ≈960×680 (không còn 880×1100 cao nghệu); MỘT tiêu đề duy nhất "Tổng quan" (thanh công cụ, không lặp trong nội dung); mục chọn thanh bên ("Tổng quan") có viên thuốc CAM thương hiệu, không phải xanh hệ thống; thẻ có nền nâng rõ, viền mờ, bóng nhẹ — đổi System Settings › Giao diện sang TỐI, thẻ vẫn tách rõ khỏi nền (không còn gần như biến mất như U1); 6 chế độ xếp LƯỚI 2 cột; KHÔNG còn dòng chân trang cố định — thay bằng một thẻ nhỏ "Đóng cửa sổ không thoát vflow…" đóng được (bấm x), mở lại app (cùng VFLOW_HOME) thì thẻ đó KHÔNG hiện lại.
51. Dọn `defaults` thật trước: `defaults export org.aios.vflow /tmp/before.plist`. Mở app với `VFLOW_HOME` CÔ LẬP, đổi mấy công tắc (chế độ, Lưu lịch sử, Hiện cửa sổ khi mở app), kéo/đổi cỡ cửa sổ, thoát app. So `defaults export org.aios.vflow /tmp/after.plist` với before.
    **Dự kiến:** KHÔNG có khoá nào đổi (mode/hasSeenWelcome/NSWindow Frame org.aios.vflow.*/showWindowOnLaunch/showMenuBarIcon/historyEnabled) — mọi thứ đã ghi vào một suite RIÊNG (tên dẫn từ `VFLOW_HOME`), không phải domain `org.aios.vflow` thật. Mở lại app KHÔNG có `VFLOW_HOME` (app thật) ⇒ vẫn dùng đúng các khoá cũ trong `org.aios.vflow` như trước U2, không bị "mất" cài đặt.
52. Tab Lịch sử: đọc chính tả vài câu trong các ngày khác nhau (đổi giờ hệ thống tạm thời hoặc chờ qua ngày — hoặc kiểm bằng `swift test --filter HistoryGroupingTests`), gõ vào ô tìm kiếm Ở THANH CÔNG CỤ (không phải trong nội dung).
    **Dự kiến:** các mục gom theo "Hôm nay"/"Hôm qua"/ngày cụ thể, mỗi dòng có biểu tượng ứng dụng đích thật (vd. biểu tượng Terminal) — ứng dụng không rõ/đã gỡ thì dùng biểu tượng chung, không vỡ layout. Chuột phải một mục ⇒ Sao chép/Sửa…/Thêm vào từ điển…/Xoá; chọn một mục rồi ⌘C ⇒ clipboard có đúng văn bản. Xoá hết lịch sử (hoặc `VFLOW_HOME` trống) ⇒ "Chưa có câu nào" kèm gợi ý giữ ⌥; tắt "Lưu lịch sử" + lịch sử trống ⇒ thông điệp "Lịch sử đang tắt" riêng.
53. Tab Lịch sử, chuột phải một mục › "Thêm vào từ điển…".
    **Dự kiến:** sheet thêm từ điển mở, "Cách nói" đã tiền điền bằng câu vừa chọn; gõ Thuật ngữ rồi Lưu ⇒ mục mới xuất hiện ở tab Từ điển.
54. Tab Từ điển/Snippets: bấm "+", gõ thuật ngữ/trigger TRÙNG một mục có sẵn.
    **Dự kiến:** thông điệp lỗi đỏ hiện NGAY KHI GÕ (không cần bấm Lưu), nút Lưu bị mờ/vô hiệu; xoá chữ trùng ⇒ lỗi biến mất, Lưu lại sáng. Thử gõ cách nói/nội dung RỖNG, hoặc thuật ngữ quá dài (>100 ký tự) ⇒ cũng báo lỗi tương ứng ngay khi gõ. Đổi sắp xếp A–Z ↔ Dùng nhiều ⇒ danh sách đổi thứ tự ngay. Xoá hết mục ⇒ trạng thái rỗng có ví dụ cụ thể ("Thêm 'deploy'…" / "link lịch hẹn → https://…").
55. HUD: `--demo-overlay ghi --demo-seconds 8` rồi `--demo-overlay khoa`, `--demo-overlay dich`, `--demo-overlay xong`, `--demo-overlay loi`.
    **Dự kiến:** viên thuốc `.regularMaterial` bo tròn; "ghi"/"khoa" có sóng âm 7 vạch ĐỘNG (vạch giữa cao nhất); "khoa" có chữ "bấm ⌥ để xong, Esc để huỷ"; "dich" có vòng xoay (không phải icon tĩnh); "xong" tự ẩn sau ~1s; "loi" tự ẩn sau vài giây, không che phím (ở đáy màn hình). Bật Giảm chuyển động rồi lặp lại "ghi" ⇒ sóng âm vẫn đổi theo mức nhưng KHÔNG hoạt ảnh mượt (nhảy tức thì).
56. Cài đặt (⌘,): nhìn thanh công cụ 4 tab.
    **Dự kiến:** mỗi tab có biểu tượng SF Symbol rõ ràng (Chung/Giọng nói/Ứng dụng/Đám mây/Dữ liệu/Phím tắt/Lịch sử & riêng tư/Nâng cao — V2 thêm 3 tab đầu), không chỉ chữ.
57. Menu thanh trạng thái (bấm biểu tượng thanh menu).
    **Dự kiến:** dòng trạng thái + biểu tượng ở đầu menu; các mục nhóm có tiêu đề nhỏ ("Cần xử lý" nếu có, "Chế độ", "Khác"); chế độ đang chọn có dấu tích; nhiều mục có icon SF Symbols. Biểu tượng thanh menu TỰ THÂN vẫn trắng/đen như cũ.
58. `client/scripts/install-app.sh` khi vflow thật ĐANG CHẠY (bản ký ổn định).
    **Dự kiến:** thoát được trong khoảng ~1-2s (không phải chờ hết 15s rồi báo lỗi như trước khi sửa) — script tiếp tục cài đè bình thường.
59. `node --test client/scripts/install-app.test.js`.
    **Dự kiến:** PASS cả hai kịch bản (thoát được ⇒ cài; cứng đầu ⇒ dừng mã khác 0, không chép đè).

## H. Chữ ký ổn định (chạy MỘT LẦN, cần chủ dự án tự duyệt)
46. `client/scripts/make-signing-identity.sh --dry-run` trước để xem các lệnh sẽ chạy (không đổi gì).
    **Dự kiến:** in ra 4 lệnh (`openssl req`, `openssl pkcs12`, `security import`, `security set-key-partition-list`), không hỏi mật khẩu, không tạo gì trong keychain.
47. `client/scripts/make-signing-identity.sh --yes`.
    **Dự kiến:** 1–2 hộp thoại hệ thống hỏi mật khẩu/Touch ID (Keychain Access) — xác nhận cho phép `codesign`/`security` dùng khoá riêng mới. Xong, `security find-identity -v -p codesigning | grep vflow` ra đúng 1 dòng "vflow Local Signing". Chạy lại script lần nữa (không cờ khác) ⇒ in "Đã có … — không làm gì thêm" rồi thoát ngay, không hỏi mật khẩu lần nữa.
48. `client/scripts/build-app.sh`.
    **Dự kiến:** dòng "ký ổn định bằng "vflow Local Signing": quyền macOS được giữ qua các lần cài" thay vì cảnh báo ad-hoc. `codesign -dvvv client/build/VFlow.app | grep Authority` ra `Authority=vflow Local Signing`.
49. Mở app đã ký ổn định lần đầu, cấp đủ 3 quyền macOS. Xoá `client/build/VFlow.app`, chạy lại `build-app.sh`, mở lại.
    **Dự kiến:** KHÔNG bị đòi cấp lại quyền (khác hẳn bản ad-hoc ở bước 28/31) — vì chữ ký (danh tính) giống hệt lần trước dù nhị phân có thể đổi byte.

## I. U4: dán an toàn, chèn lại câu vừa rồi, dự phòng khi che biểu tượng, nút Cài đặt, phím tắt tuỳ chỉnh, micro/VAD
60. (Q1 — hồi quy "phải bấm ⌘V") Giữ ⌥ trái nói một câu ngắn vào MỖI app sau, rồi nhả phím: Notes, Terminal, Chrome (ô tìm kiếm/ô soạn Gmail), Zalo, Claude Code/Orca, và một app Electron bất kỳ (VS Code/Slack).
    **Dự kiến:** ngay khi nhả phím chữ TỰ HIỆN vào ô đang gõ, HUD "Xong"; KHÔNG BAO GIỜ hiện "Đã chép — bấm ⌘V" và anh KHÔNG phải tự bấm ⌘V ở bất kỳ app nào kể cả app có Accessibility không chuẩn (Zalo, Chrome, Electron). Clipboard CŨ (trước khi nói) được khôi phục nguyên vẹn sau ~0,4 giây.
61. Giữ ⌥ nói một câu, trong lúc HUD "Đang dịch" thì bấm vào cửa sổ vflow (làm vflow thành app phía trước), rồi chờ kết quả.
    **Dự kiến:** vflow tự đưa app đích (app đang focus lúc bắt đầu ghi) lên trước rồi dán vào đó, không dán vào cửa sổ vflow. Nếu thay vào đó anh chủ động chuyển sang một app KHÁC (không phải vflow) trong lúc dịch ⇒ chữ dán vào app đó (không bị giật focus về app cũ). Lặp lại với "nhấn enter" ở cuối câu (Enter gửi sau khi dán), với Command Mode (⌥+⌃) và với ghi hands-free (đúp ⌥): cả ba đều dán ngay như trên.
62. Đọc chính tả một câu bất kỳ, sau đó bấm biểu tượng thanh menu › "Chèn lại câu vừa rồi" (hoặc chuột phải biểu tượng Dock › cùng mục, hoặc ⌥⌘V) khi đang focus ô nhập khác.
    **Dự kiến:** câu vừa nói được chèn lại đúng y nguyên vào ô đang focus (cùng cách dán/khôi phục clipboard như dictation). Cài đặt › Dữ liệu & Riêng tư tắt "Lưu lịch sử", lặp lại với MỘT câu mới nói trong phiên này ⇒ vẫn chèn lại được (nhớ trong RAM); thoát app rồi mở lại (lịch sử đang tắt) rồi bấm "Chèn lại câu vừa rồi" ngay ⇒ HUD "Chưa có câu nào" (bộ nhớ phiên đã mất).
63. Chưa nói câu nào từ lúc mở app (lịch sử đang tắt) rồi bấm "Chèn lại câu vừa rồi".
    **Dự kiến:** HUD "Chưa có câu nào", không dán gì, không đổi clipboard.
64. Chuột phải (hoặc giữ) biểu tượng Dock của vflow.
    **Dự kiến:** menu hiện ra CÙNG các mục với menu thanh trạng thái (dòng trạng thái, Chế độ có dấu tích, Chèn lại câu vừa rồi, Mở cửa sổ vflow, Cài đặt…, Thoát vflow…) — không thiếu mục nào, không có mục chỉ-riêng-Dock.
65. Mở nhiều ứng dụng có biểu tượng thanh menu cho tới khi thanh menu chật (hoặc dùng MacBook có notch, kéo biểu tượng vflow về gần notch bằng ⌘-kéo) để biểu tượng vflow bị che/ẩn.
    **Dự kiến:** tab Tổng quan tự hiện thẻ cam "Biểu tượng thanh menu có thể đang bị che" với đúng câu hướng dẫn, nút "Mở Cài đặt › Chung", và nút đóng (x). Đóng thẻ, khởi động lại app (biểu tượng vẫn bị che) ⇒ thẻ KHÔNG hiện lại trong cùng ngày; đợi qua ngày hôm sau (hoặc đổi giờ hệ thống — chỉ để thử) ⇒ hiện lại nếu vẫn bị che. Bỏ che (kéo biểu tượng ra, hoặc thoát vài app) ⇒ thẻ tự biến mất (không cần đóng tay).
66. Cài đặt (⌘,): nhìn thanh công cụ.
    **Dự kiến:** 8 tab (Chung/Giọng nói/Ứng dụng/Đám mây/Dữ liệu/Phím tắt/Lịch sử & riêng tư/Nâng cao) — V2 thêm Giọng nói/Ứng dụng/Dữ liệu.
67. Cửa sổ chính "vflow": nhìn chân thanh bên và thanh công cụ.
    **Dự kiến:** chân thanh bên có nút bánh răng "Cài đặt" kèm chữ "⌘," mờ bên phải; thanh công cụ (góc trên-phải cửa sổ) cũng có nút bánh răng riêng. Bấm MỘT trong hai (hoặc ⌘, hoặc menu/Dock) ⇒ luôn mở đúng MỘT cửa sổ Cài đặt (không có cửa sổ thứ hai).
68. Cài đặt › Giọng nói: đổi "Phím giữ để nói" thành "⌃ trái", đổi "Phím Command Mode" thành "⌥ trái" (đảo ngược mặc định).
    **Dự kiến:** không có cảnh báo trùng (hai phím khác nhau). Thử giữ ⌃ trái ở Terminal ⇒ ghi âm như trước đây ⌥ trái làm; giữ ⌃ trái rồi bấm thêm ⌥ trái trong 400ms đầu ⇒ vào Command Mode. ⌥ trái một mình giờ KHÔNG còn bắt đầu ghi nữa.
69. Cài đặt › Giọng nói: đổi cả hai phím về CÙNG một phím (vd. cả hai đều "⌥ trái").
    **Dự kiến:** hiện cảnh báo đỏ tiếng Việt về trùng phím ngay trong Cài đặt.
70. Cài đặt › Giọng nói: bấm "Đặt lại mặc định".
    **Dự kiến:** cả hai phím về ⌥ trái/⌃ trái, tổ hợp "Chèn lại câu vừa rồi" về ⌥⌘V.
71. Đang giữ ⌥ trái ghi âm (chưa nhả), MỞ cửa sổ Cài đặt › Giọng nói ở một lúc khác đổi phím giữ sang "⌃ trái" (nếu máy cho tương tác cả hai cùng lúc — thử bằng cách đổi cài đặt rồi NGAY LẬP TỨC nhả ⌥ đang giữ).
    **Dự kiến:** lượt ghi ĐANG CHẠY vẫn kết thúc đúng khi nhả ⌥ (không bị "mất nút nhả" vì đổi cấu hình giữa chừng) — cấu hình mới chỉ áp dụng cho LẦN SAU.
72. Cài đặt › Chung › Micro: mở danh sách.
    **Dự kiến:** thấy "Mặc định hệ thống" + micro trong máy (và micro ngoài nếu có cắm). Chọn micro trong máy (hoặc để mặc định), ghi thử ⇒ vẫn nghe/chèn chữ bình thường (KHÔNG có micro ngoài để thử đổi thật trong môi trường dựng — chủ dự án tự thử nếu có tai nghe/micro USB, xem giới hạn đã biết trong README).
73. (Chỉ nếu có micro ngoài) Chọn micro ngoài ở Cài đặt, rút nó ra, rồi ghi thử.
    **Dự kiến:** HUD báo một lần "Micro đã chọn không còn — dùng micro mặc định"; Cài đặt tự về "Mặc định hệ thống"; ghi âm vẫn hoạt động bằng micro trong máy.
74. Cài đặt › Chung: đặt "Tự dừng khi im lặng" = 3 giây. Đúp ⌥ (ghi khoá), nói một câu ngắn, NGỪNG nói hẳn (im lặng thật, đừng gõ bàn phím gây ồn).
    **Dự kiến:** sau ~2 giây im lặng HUD hiện đếm ngược ("Im lặng — tự dừng sau N giây"), tới khi hết thì TỰ gửi như bấm ⌥ lần nữa — không cần bấm gì. Lặp lại nhưng nói-ngừng ngắn (< 3s)-nói tiếp trong lúc đang đếm ngược ⇒ KHÔNG bị cắt giữa câu, đếm ngược biến mất rồi chỉ xuất hiện lại nếu im lặng đủ lâu sau khi nói xong.
75. Cài đặt › Chung: đặt "Tự dừng khi im lặng" = Tắt (0). Đúp ⌥, nói rồi im lặng thật lâu (> 1 phút).
    **Dự kiến:** KHÔNG tự dừng vì im lặng — chỉ tự dừng ở giới hạn thời gian ghi tối đa (xem bước 76).
76. Đúp ⌥ (ghi khoá), giữ im lặng/nói liên tục quá 120 giây. **V2**: `/healthz` giờ báo `max_audio_seconds:1200` — kiểm bằng `curl -s 127.0.0.1:7611/healthz | grep max_audio_seconds` trước khi thử bước này; giới hạn ghi thật sự của hands-free giờ cao hơn 120s (kẹp [120,1200], xem `VFlowCore.RecordingLimit`) — nếu anh muốn thử đúng giới hạn 120s cũ thì tắt engine thật và dùng bản engine giả/cũ, hoặc chấp nhận ghi lâu hơn để thấy cảnh báo ở mốc mới.
    **Dự kiến:** cảnh báo "Còn khoảng 30 giây sẽ tự gửi" đúng ~30 giây trước khi chạm giới hạn thật (1200s, không còn 120s cố định), rồi tự dừng+gửi — không mất dữ liệu đã ghi.

## K. V2: Thống kê, Cài đặt mở rộng, Xem chữ chạy trực tiếp, Gợi ý từ điển, Degraded

77. Mở tab **Thống kê** (⌘2) lần đầu (chưa nói câu nào trong `VFLOW_HOME` đang dùng, hoặc dùng một `VFLOW_HOME` trống mới).
    **Dự kiến:** dòng chào lớn "Chưa có câu nào. Giữ ⌥ trái và nói thử." rồi một khối trống đẹp (icon sóng âm + gợi ý) — không có số 0 giả nào ở dưới.
78. Nói vài chục câu rải trong vài ngày (hoặc dùng dữ liệu mẫu — xem `client/scripts/snapshot-seed.mjs`/`snapshot.sh` để xem trước hình dạng), rồi mở lại tab Thống kê.
    **Dự kiến:** dòng chào đổi theo đúng ngưỡng số từ (1–99/100–999/1.000–9.999/≥10.000, định dạng dấu chấm ngăn nghìn); 4 thẻ số đúng (Từ đã nói, WPM trung bình — "—" nếu tổng thời lượng ghi âm thật < 1 phút, Chuỗi ngày, Chuỗi dài nhất); lưới "Hoạt động N tuần" có ô HÔM NAY viền nổi, ô ngày tương lai không vẽ, di chuột vào một ô có tooltip "dd/mm/yyyy: N từ · N câu"; "Từ của bạn đi đâu" liệt kê đúng ứng dụng đã nói vào (biểu tượng thật nếu app còn cài, "Không rõ" nếu không). Đọc thêm một câu ở Terminal ⇒ quay lại tab Thống kê (không cần bấm làm mới) ⇒ số liệu đã cập nhật theo câu vừa nói.
79. Cài đặt › Dữ liệu & Riêng tư: tắt công tắc "Thu thập thống kê", mở tab Thống kê.
    **Dự kiến:** thẻ "Thống kê đang tắt" kèm nút "Bật" (bật lại ngay, không cần vào Cài đặt) và "Mở Cài đặt › Dữ liệu & Riêng tư". Nói thêm một câu trong lúc đang tắt rồi bật lại ⇒ câu lúc tắt KHÔNG được đếm (số không tăng thêm vì câu đó), dữ liệu cũ trước khi tắt vẫn còn nguyên.
80. Cài đặt › Dữ liệu & Riêng tư › "Xoá thống kê…", xác nhận.
    **Dự kiến:** hộp thoại xác nhận tiếng Việt rõ ràng; sau khi xoá, tab Thống kê về lại trạng thái "Chưa có câu nào" dù lịch sử (tab Lịch sử) KHÔNG bị xoá.
81. Cài đặt › Giọng nói: tắt "Ra lệnh dấu câu bằng giọng". Giữ ⌥ nói "mở ngoặc xin chào xuống dòng tạm biệt dấu chấm".
    **Dự kiến:** chữ chèn giữ NGUYÊN các cụm "mở ngoặc"/"xuống dòng"/"dấu chấm" dưới dạng chữ (không đổi thành `(`/xuống dòng thật/`.`). Bật lại công tắc, nói lại CÙNG câu đó.
    **Dự kiến:** chữ chèn có `(` thật, xuống dòng thật giữa "xin chào" và "tạm biệt", và dấu `.` dính liền cuối câu (không có khoảng trắng thừa trước dấu chấm).
82. Cài đặt › Giọng nói: bật "Chế độ nói nhỏ", thử nói rất khẽ (gần như thì thầm) ở nơi yên tĩnh.
    **Dự kiến:** vẫn nhận dạng được tốt hơn rõ rệt so với lúc tắt công tắc này (so sánh bằng cách tắt rồi nói y hệt lại) — đây là khuếch đại trong máy, không đổi quyết định "im lặng hoàn toàn" (`silence:true` vẫn đúng khi thật sự không nói gì).
83. Cài đặt › Giọng nói: đổi "Phím giữ để nói" thành **"⌥ phải"**.
    **Dự kiến:** giữ ⌥ TRÁI giờ KHÔNG còn bắt đầu ghi (không phản ứng gì); giữ ⌥ PHẢI ≥200ms ⇒ "Đang nghe" như ⌥ trái làm trước đây; mọi hành vi khác (đúp để khoá, Esc huỷ, giới hạn thời gian) giữ nguyên với phím mới. Đặt lại "Đặt lại mặc định" trước khi tiếp tục các bước khác (nhiều bước trong tài liệu này giả định ⌥ trái).
84. Cài đặt › Chung › Micro: đổi từ "Mặc định hệ thống" sang một micro CỤ THỂ trong danh sách (micro trong máy nếu không có micro ngoài), đọc chính tả vài câu, rồi đổi LẠI "Mặc định hệ thống".
    **Dự kiến:** mỗi lần đổi, lần ghi KẾ TIẾP dùng đúng micro vừa chọn (nếu có nhiều micro để so sánh bằng tai/chỉ báo hệ thống); không có lỗi/crash khi đổi qua lại; micro đã chọn được NHỚ lại sau khi thoát/mở lại app (đổi `VFLOW_HOME` để kiểm cô lập nếu cần).
85. Cài đặt › Giọng nói: bật "Hiện chữ đang nghe lúc nói" (mặc định đã bật — V2). Giữ ⌥ trái, nói một câu DÀI (≥10 giây, ví dụ đọc một đoạn văn), quan sát HUD TRONG LÚC đang nói (chưa nhả phím).
    **Dự kiến:** sau khoảng 1 giây kể từ lúc bắt đầu nói, một dòng CHỮ MỜ (nhạt hơn dòng "Đang nghe") xuất hiện dưới thanh trạng thái, cập nhật dần theo những gì đang nói (tối đa 2 dòng, chỉ phần cuối nếu câu dài) — chữ này KHÔNG được chèn vào ô đang gõ (ô đích vẫn trống cho tới khi nhả phím). Nhả phím ⇒ chữ mờ biến mất, thay bằng kết quả CUỐI CÙNG thật (`/v1/transcribe`, có thể khác đôi chút so với chữ mờ lúc đang nói — đó là bình thường, chữ mờ chỉ là bản thô tạm).
86. Tắt công tắc "Hiện chữ đang nghe lúc nói" ở Cài đặt › Giọng nói, lặp lại bước 85.
    **Dự kiến:** không có dòng chữ mờ nào xuất hiện trong lúc nói; kết quả cuối sau khi nhả phím vẫn đúng như trước (tính năng chỉ ẩn/hiện phần xem trước, không đổi kết quả thật).
87. (Cần mạng tới 9Router) Cài đặt › Nâng cao: tắt "Cho phép gửi chữ qua 9Router". Chọn chế độ **Gọn**, giữ ⌥ nói một câu.
    **Dự kiến:** HUD báo ngắn gọn "Đám mây đang tắt — dùng Làm sạch" (không phải lỗi đỏ dài dòng); chữ vẫn được chèn (bản Làm sạch, không có LLM); mở tab Lịch sử, mục vừa tạo có đánh dấu suy giảm (nếu cột đó hiển thị ở UI) hoặc ít nhất không có gì mất mát (text vẫn đúng). Bật lại công tắc.
88. Cài đặt › Ứng dụng: bấm "Chọn ứng dụng…", chọn Terminal.app (hoặc app bất kỳ trong `/Applications`), đặt chế độ "Lập trình". Mở Terminal, chọn chế độ **Tự động** (không chọn tay), giữ ⌥ nói một câu có từ kỹ thuật (vd. "git_commit_message viết thường nối gạch dưới").
    **Dự kiến:** dù đang ở chế độ Tự động, Terminal vẫn được xử lý theo luật vừa đặt (Lập trình) thay vì luật mặc định của `auto` — câu được tách theo quy tắc lập trình (`git_commit_message`, không phải chữ thường bình thường).
89. Cài đặt › Ứng dụng: bấm "Từ ứng dụng đang chạy…", chọn một app đang mở, đặt chế độ **Gọn**. Tắt đám mây (Cài đặt › Nâng cao) trong lúc luật đó vẫn còn.
    **Dự kiến:** hàng luật đó hiện nhãn cảnh báo cam "đám mây tắt — rơi về Làm sạch" (không phải nhãn xám "gửi chữ qua 9Router" như lúc đám mây đang bật). Xoá luật đó bằng nút thùng rác.
    **Dự kiến:** hàng biến mất ngay, không cần Lưu riêng.
90. Cài đặt › Dữ liệu & Riêng tư: bấm "Xuất dữ liệu…" (để công tắc "Gồm lịch sử khi xuất" TẮT), lưu vào `~/Desktop/vflow-export.json`.
    **Dự kiến:** hộp thoại lưu tệp chuẩn macOS hiện ra; sau khi lưu, `ls -l ~/Desktop/vflow-export.json` cho quyền `-rw-------` (0600); mở tệp bằng trình soạn thảo — có `dictionary`/`snippets`/`settings`/`stats`, KHÔNG có `history`, và chắc chắn KHÔNG có chuỗi nào chứa khoá 9Router hay token (tìm `grep -i "key\|token"` trong tệp, chỉ nên thấy tên trường `llm_model`, không thấy giá trị bí mật nào).
91. Cài đặt › Dữ liệu & Riêng tư: sửa tay tệp vừa xuất — đổi `"term"` của một mục `dictionary` thành chuỗi RỖNG `""` — rồi bấm "Nhập dữ liệu…", chọn đúng tệp đã sửa hỏng đó.
    **Dự kiến:** thông báo lỗi cụ thể (có chữ "dictionary", chỉ đúng chỉ số mục hỏng) — và SAU ĐÓ kiểm tab Từ điển: KHÔNG có gì bị thêm/đổi (kiểm bằng đếm số mục trước và sau, phải bằng nhau) — gói hỏng một phần bị từ chối CẢ GÓI, không "nhập được phần còn lại".
92. Sửa lại tệp xuất (bỏ chỗ hỏng ở bước 91, hoặc xuất lại tệp mới sạch), Cài đặt › Dữ liệu & Riêng tư › "Nhập dữ liệu…" (Gộp).
    **Dự kiến:** thông báo kết quả cụ thể dạng "Đã nhập: từ điển N, snippets N, cài đặt N, thống kê N ngày, lịch sử N." — số khớp đúng nội dung tệp.
93. Tab Từ điển: đọc chính tả một câu có thuật ngữ chưa có trong từ điển (vd. tên một thư viện lạ), rồi SỬA lại câu đó ở tab Lịch sử đúng thành thuật ngữ đó HAI LẦN (hai lần sửa riêng biệt, cùng một cặp trước/sau).
    **Dự kiến:** sau lần sửa thứ hai, mở tab Từ điển ⇒ khối "Gợi ý từ lần anh sửa" xuất hiện phía trên danh sách với đúng thuật ngữ, cách nói sai, "Gặp 2 lần". Bấm "Thêm vào từ điển" ⇒ mở sheet Thêm mục đã điền sẵn thuật ngữ + cách nói, Lưu ⇒ gợi ý đó biến mất khỏi danh sách và mục mới xuất hiện trong từ điển chính. Thử lại với một gợi ý khác (nếu có) bằng nút "Bỏ qua" ⇒ gợi ý đó biến mất và KHÔNG quay lại kể cả sau khi mở lại app.
94. Cài đặt › Dữ liệu & Riêng tư: bấm "Sao chép chẩn đoán", dán (⌘V) vào một trình soạn thảo.
    **Dự kiến:** nội dung là JSON có `engine_version`/`model`/`settings`/`counts`/`recent_errors`; tìm (⌘F) chuỗi "key"/"token" trong nội dung dán ra — không thấy giá trị bí mật nào (chỉ tên trường, nếu có). Bấm "Lưu chẩn đoán…" lưu ra tệp, kiểm quyền tệp `-rw-------` như bước 90.

## L. Nhóm A (V3): dạy từ bằng giọng, lưu âm thanh để nghe lại, HUD, giao diện, "Hôm nay", ký hiệu theo ngữ cảnh, độ trễ ghi

Dành cho chủ dự án, tự thử trên máy thật. Không cần biết lập trình: chỉ làm theo từng bước rồi so với **KỲ VỌNG**; thấy **DẤU HIỆU SAI** thì ghi lại bước đó + chụp/chép nguyên văn thông báo trên màn hình.
Chuẩn bị: đã dựng và mở bản mới (`client/scripts/build-app.sh`, rồi mở `client/build/VFlow.app`); micro và quyền macOS đã cấp (mục A ở trên). Bước nào nhắc dòng lệnh thì dán vào Terminal.
(Phần engine đã có bộ kiểm tự động riêng: `node client/scripts/probe-group-a.mjs` — chạy được trước khi thử tay, không đụng dữ liệu thật; xem `client/README.md`.)

**L1. Dạy một từ khó bằng giọng**
1. Cửa sổ "vflow" › tab **Từ điển** › bấm **"Dạy từ bằng giọng…"**.
2. Ở ô "Từ đúng" gõ một từ mà vflow hay nghe sai (ví dụ tên anh, "Supabase", "Orca").
3. Bấm **"Bắt đầu ghi"**, nói rõ đúng từ đó (một mình, ~1–2 giây), bấm **"Dừng ghi"**. Lặp lại 3 lần, mỗi lần nói hơi khác (nhanh/chậm/giọng tự nhiên).
4. Chọn các cách nói muốn giữ rồi bấm **"Lưu vào từ điển"**. Sang tab Từ điển xem mục vừa lưu; sau đó đọc chính tả một câu có chứa từ đó vào Notes.
   **KỲ VỌNG:** mỗi lần ghi xuất hiện một dòng "1. Nghe ra: …" (chữ máy nghe được, viết thường, CHƯA qua từ điển — nên có thể sai, đó chính là điều cần dạy); đủ 3–5 lần thì nút ghi tạm khoá; danh sách "Cách nói sẽ lưu" gom các cách nghe khác nhau (không trùng); sau khi lưu, mục có thuật ngữ đúng + các cách nói đó, câu đọc ở Notes ra ĐÚNG từ đã dạy. Nếu máy nghe ra y hệt từ đã gõ, thấy dòng "Engine nghe ra đúng như từ đã nhập — không có cách nói nào cần dạy thêm.".
   **DẤU HIỆU SAI:** không ra dòng "Nghe ra" sau khi dừng ghi (hoặc ra lỗi mơ hồ); ghi quá 10 giây mà không báo gì; lưu xong mục bị TRÙNG với mục cũ thay vì gộp; câu đọc ở Notes vẫn ra từ cũ; **sau khi dạy, tab Lịch sử có thêm câu mới hoặc số "từ" ở tab Thống kê/viên "Hôm nay" tăng** (dạy từ KHÔNG được tính là đọc chính tả); hoặc bật "Lưu âm thanh" (L2) rồi dạy từ mà `ls ~/.vflow/audio` có thêm tệp (dạy từ không được lưu âm thanh).

**L2. Bật lưu âm thanh rồi nghe lại một câu (riêng tư: mặc định TẮT)**
1. Lần đầu: Cài đặt (⌘,) › **Dữ liệu** › mục **"Lưu âm thanh để nghe lại"**. Chưa bật gì: công tắc phải đang TẮT. Chạy `ls ~/.vflow/audio` ⇒ báo không có thư mục (hoặc rỗng).
2. Đọc chính tả một câu bình thường (công tắc vẫn tắt). Tab **Lịch sử**: câu đó KHÔNG có nút nghe lại.
3. Bật công tắc. Hộp thoại hỏi xác nhận phải nói rõ: lưu ở `~/.vflow/audio` trên máy này, không gửi đi đâu, giới hạn dung lượng/số ngày, tệp quyền 0600, xoá được bất cứ lúc nào. Bấm **"Bật lưu âm thanh"**.
4. Đọc chính tả một câu (ví dụ "hôm nay trời đẹp quá"). Mở tab Lịch sử, bấm nút nghe lại ở dòng câu đó (KHÔNG tự phát khi mở tab), rồi bấm lại để dừng.
5. Kiểm tệp: `ls -ld ~/.vflow/audio && ls -l ~/.vflow/audio`.
6. Cài đặt › Dữ liệu & Riêng tư: đọc dòng dung lượng đã lưu, bấm **"Xuất ZIP…"**, lưu ra Desktop, nhấp đúp mở ZIP trong Finder; mở `index.json` bằng TextEdit.
7. Chuột phải câu đó trong Lịch sử › **"Xoá âm thanh của câu này"**; rồi đọc thêm vài câu và Cài đặt › Dữ liệu & Riêng tư › **"Xoá toàn bộ âm thanh…"** (xác nhận). Chạy lại `ls ~/.vflow/audio`.
8. Tắt công tắc "Lưu lịch sử" ở Cài đặt › Dữ liệu & Riêng tư (khi lưu âm thanh đang bật).
   **KỲ VỌNG:** (1–2) mặc định tắt, không có tệp, không có nút nghe lại. (3) hộp thoại đúng nội dung trên. (4) nghe đúng giọng và đúng câu mình vừa nói; nút đổi thành "dừng". (5) thư mục `drwx------` (0700), mỗi tệp `.wav` `-rw-------` (0600), tên kiểu `tr_….wav`; có `index.json` 0600; số tệp = số câu đã đọc kể từ lúc bật. (6) ZIP mở được, có đủ tệp `.wav` nghe được + `index.json` chỉ có `id`, `at`, `audio_ms`, `app`, `mode` — KHÔNG có chữ của câu nói. (7) xoá một: nút nghe lại của câu đó mất, các câu khác vẫn nghe được; xoá hết: thông báo "Đã xoá N tệp âm thanh.", `ls` không còn `.wav`, các câu trong Lịch sử vẫn còn (chỉ mất âm thanh). (8) tự tắt công tắc lưu âm thanh kèm thông báo "Đã tự tắt lưu âm thanh vì Lịch sử đang tắt."; bật lại Lịch sử KHÔNG tự bật lại lưu âm thanh.
   **DẤU HIỆU SAI:** công tắc tự bật sẵn; có tệp `.wav` trong `~/.vflow/audio` khi công tắc tắt (kể cả câu im lặng, câu dạy từ, lệnh Command Mode); quyền tệp/thư mục khác 0600/0700; nghe ra giọng/câu khác; nút nghe lại tự phát khi mở tab; `index.json` hay ZIP chứa chữ của câu nói; sau "Xoá toàn bộ" `ls` vẫn còn `.wav`; thông báo lỗi tiếng Anh/mã máy.
   Kiểm riêng tư thêm (một lần): Cài đặt › Dữ liệu & Riêng tư › **"Xuất dữ liệu…"** (để công tắc "Gồm lịch sử" tắt) và **"Sao chép chẩn đoán"** rồi dán vào trình soạn thảo. **KỲ VỌNG:** chỉ là văn bản JSON nhỏ (vài KB); tìm "audio" chỉ thấy tên các cờ cài đặt (`audio_history`…), KHÔNG có đường dẫn `/Users/…`, KHÔNG có dữ liệu âm thanh, token hay khoá. **SAI:** tệp xuất/chẩn đoán lớn bất thường, có chuỗi "RIFF"/"WAVE", đường dẫn tuyệt đối thư mục cá nhân, hoặc token.
   Giới hạn dung lượng/hạn ngày (tự kiểm ở mức engine bằng `probe-group-a.mjs`; thử tay nếu muốn): đặt giới hạn nhỏ nhất (50 MB) và 1 ngày ở Cài đặt › Dữ liệu & Riêng tư rồi đọc nhiều câu dài — **KỲ VỌNG:** tổng dung lượng hiển thị không vượt giới hạn, bản CŨ nhất bị xoá trước; **SAI:** dung lượng vượt giới hạn mà không bản nào bị xoá, hoặc bản MỚI nhất bị xoá thay vì bản cũ.

**L3. Đổi vị trí và cỡ thanh ghi âm (HUD) sang cạnh notch**
1. Cài đặt › **Chung** › mục **"Thanh ghi âm"**: Vị trí = **"Cạnh notch"**, Cỡ = **"Lớn"**.
2. Mở Notes, giữ ⌥ trái nói một câu DÀI (≥ 10 giây, vừa nói vừa nhìn lên mép trên màn hình), nhả.
3. Đổi Cỡ thành **"Vừa"**, rồi **"Gọn"**, lặp lại bước 2 mỗi lần. Cuối cùng đặt lại Vị trí = "Dưới màn hình", Cỡ như ý.
   **KỲ VỌNG:** HUD hiện ở GIỮA mép trên màn hình, ngay DƯỚI thanh menu và KHÔNG đè lên notch (MacBook có notch; trên màn ngoài không notch vẫn nằm dưới thanh menu); không cướp focus (con trỏ vẫn ở Notes, chữ vẫn dán đúng chỗ). "Lớn" hiện tối đa 4 dòng chữ chạy trực tiếp, rộng hơn; "Vừa" 2 dòng; "Gọn" chỉ có viên trạng thái + sóng âm (không dòng chữ). Đổi cài đặt có hiệu lực từ LẦN GHI KẾ TIẾP (không nhảy giữa lúc đang ghi).
   **DẤU HIỆU SAI:** HUD nằm đè lên notch/bị notch cắt; hiện ngoài màn hình hoặc sai màn hình; chữ chạy trực tiếp bị cắt giữa chừng, tràn khỏi khung "Lớn"; "Gọn" vẫn hiện dòng chữ; sau khi chọn "Cạnh notch" thoát/mở lại app thì quay về vị trí cũ (phải được NHỚ).

**L4. Đổi giao diện Sáng/Tối**
1. Cài đặt › **Chung** › mục **"Giao diện"** chọn **"Tối"**; xem cửa sổ chính (mỗi tab: Tổng quan, Thống kê, Lịch sử, Từ điển, Snippets) và cửa sổ Cài đặt. Chọn **"Sáng"**, xem lại. Chọn **"Hệ thống"**.
2. Dùng nút "Giao diện" ở thanh công cụ cửa sổ chính (cùng chức năng), thoát hẳn app rồi mở lại.
3. Đổi System Settings › Giao diện của macOS sang Sáng/Tối trong lúc vflow đang ở "Sáng" rồi ở "Hệ thống".
   **KỲ VỌNG:** đổi NGAY cho mọi cửa sổ vflow (kể cả đang mở), không cần mở lại; chữ đọc rõ, thẻ/viền tách khỏi nền ở cả hai kiểu; lựa chọn được nhớ sau khi mở lại; ở "Sáng"/"Tối" cố định thì đổi macOS KHÔNG làm vflow đổi theo, ở "Hệ thống" thì đổi theo macOS; không ứng dụng nào khác bị đổi giao diện.
   **DẤU HIỆU SAI:** chỉ một cửa sổ đổi, cửa sổ kia giữ nguyên; chữ xám nhạt khó đọc/thẻ gần biến mất ở Tối; chọn "Sáng" nhưng vẫn theo macOS; mở lại app quên lựa chọn; nhấp nháy sáng-tối khi đổi.

**L5. Xem viên "Hôm nay"**
1. Dùng một thư mục dữ liệu trống để thấy trạng thái đầu: `VFLOW_HOME=/tmp/vflow-nhomA ./client/build/VFlow.app/Contents/MacOS/VFlow` (hoặc dùng ngày chưa nói câu nào). Nhìn góc thanh công cụ cửa sổ chính.
2. Đọc chính tả một câu (khoảng 10 từ). Nhìn lại viên.
3. Bấm vào viên.
4. Mở "Dạy từ bằng giọng…" (L1) dạy một từ rồi nhìn lại số trên viên.
   **KỲ VỌNG:** (1) chưa có số thật thì viên ẨN (không hiện "0 từ" giả); (2) sau khi chèn chữ xong viên hiện "Hôm nay: N từ" với N khớp số từ đã nói (gần bằng số từ của câu); (3) bấm mở tab **Thống kê**, số ở đó (hôm nay) trùng viên; (4) dạy từ KHÔNG làm N tăng. Sang ngày mới (hoặc đổi giờ hệ thống thử) viên về trạng thái ẩn/0 theo ngày mới, không cộng dồn ngày cũ.
   **DẤU HIỆU SAI:** viên hiện "0 từ"; số lệch rõ so với tab Thống kê; N tăng khi dạy từ hoặc khi huỷ/không nghe thấy gì; bấm viên không có gì xảy ra; chữ trong viên khó đọc ở một trong hai giao diện Sáng/Tối.

**L6. "gạch chéo", "a còng" trong Terminal và trong Notes**
1. Đặt chế độ **Tự động**. Mở **Terminal**, bấm vào dòng lệnh, giữ ⌥ trái nói đúng câu: "gửi file backup gạch chéo main cho an a còng example", nhả.
2. Mở **Notes**, nói CÙNG câu y hệt.
3. Terminal: nói "mở trang https hai chấm hai gạch chéo example".  Notes: nói cùng câu.
4. (Nếu dùng Slack) ở Slack gõ vào ô soạn tin, nói "gạch chéo giúp đỡ".
   **KỲ VỌNG:** Terminal ra `gửi file backup/main cho an@example` (ký hiệu thật, không còn chữ "gạch chéo"/"a còng"); Notes giữ NGUYÊN chữ: `gửi file backup gạch chéo main cho an a còng example` (lời nói thường, không bị đổi thành ký hiệu). Bước 3: Terminal ra `https://example`; Notes giữ nguyên chữ. Slack: `/giúp đỡ`. Ứng dụng nằm ngoài danh sách terminal/IDE/Claude/chat nhóm (Notes, Mail, TextEdit, Chrome…) luôn giữ chữ. (Đã biết, nhỏ: ở chế độ Thường/Làm sạch trong ứng dụng thuộc danh sách, câu kết thúc đúng bằng "a còng <tên>" có thể thừa MỘT dấu cách cuối.)
   **DẤU HIỆU SAI:** Notes bị đổi thành `/` hoặc `@` (đổi nhầm ở ứng dụng thường); Terminal vẫn ra chữ "gạch chéo" hoặc "a còng" (chỉ đổi được một nửa); mất chữ lân cận (vd. "an@example" nuốt mất "cho"); câu như "chúng ta nói về gạch chéo trong toán học" ở Notes bị đổi mất.
   Tắt thử (tuỳ chọn, chưa có công tắc trên giao diện): `curl -s -X PUT 127.0.0.1:7611/v1/settings -H "Authorization: Bearer $(cat ~/.vflow/token)" -H 'content-type: application/json' -d '{"context_symbols":false}'` rồi nói lại câu bước 1 ở Terminal ⇒ **KỲ VỌNG:** giữ chữ ở mọi ứng dụng; đặt lại bằng cùng lệnh với `true`.

**L7. Xem độ trễ bắt đầu ghi trong Cài đặt › Nâng cao**
1. Cài đặt › **Nâng cao** › mục **"Độ trễ bắt đầu ghi"** khi mới mở app, chưa ghi lần nào.
2. Giữ ⌥ trái ghi vài lượt (5–10 lượt, cả kiểu giữ phím lẫn đúp ⌥), quay lại mục đó (cửa sổ Cài đặt có thể để mở sẵn).
3. Esc huỷ một lượt ngay khi vừa bấm; rồi thoát/mở lại app, xem lại mục.
   **KỲ VỌNG:** (1) hiện "Chưa có lượt ghi nào trong phiên này" (KHÔNG phải "0 ms"); (2) mỗi lượt thật cập nhật con số "Từ nhấn phím tới khối âm thanh đầu" (trung vị + lượt gần nhất, đơn vị ms; thường vài chục đến vài trăm ms); (3) lượt bị Esc huỷ trước khi có âm thanh KHÔNG tạo mẫu; mở lại app thì về "Chưa có lượt ghi nào…" (chỉ giữ trong bộ nhớ, tối đa 50 lượt gần nhất, không ghi đĩa, không chứa nội dung giọng nói — đúng như dòng chú thích dưới mục đó).
   **DẤU HIỆU SAI:** hiện "0 ms" khi chưa có lượt; con số vô lý (hàng chục giây hoặc âm); số lượt đo nhiều hơn số lượt ghi thật; lượt Esc vẫn làm đổi số; mở lại app vẫn còn số cũ.

**L8. Chạy bộ kiểm tự động của engine (một lệnh)**
- `node client/scripts/probe-group-a.mjs` — dựng engine thử ở cổng ngẫu nhiên 27800–27899 trong thư mục tạm (KHÔNG đụng `~/.vflow`, KHÔNG dùng cổng 7611), in bảng PASS/FAIL tiếng Việt cho teach, lưu âm thanh, ngân sách/hạn, xoá, path traversal, ZIP, rò rỉ riêng tư, ký hiệu theo ngữ cảnh, cài đặt; tự dọn. **KỲ VỌNG:** dòng cuối "N PASS, 0 FAIL", thoát mã 0, dòng "Dọn dẹp: engine … đã tắt; thư mục tạm đã xoá.". **SAI:** có FAIL (nhất là mục "Rò rỉ riêng tư" hay "Xoá và path traversal" — nghiêm trọng, dừng dùng tính năng lưu âm thanh và báo ngay).

## M. Q2: micro bị ngắt/đổi tuyến giữa lượt (CHỈ kiểm được trên máy thật của chủ dự án)

Lỗi gốc: thông báo `AVAudioEngineConfigurationChange` (bắn rất thường, vd. mỗi khi chọn micro cụ thể ở Cài đặt, hoặc khi tai nghe Bluetooth đổi tuyến) từng bị coi là "micro bị rút" ⇒ huỷ lượt + thẻ đỏ "Micro không dùng được: thiết bị micro thay đổi hoặc bị rút". Nay: kiểm trạng thái thật, dựng lại engine ÊM, giữ nguyên âm thanh đã thu. Cần bản mới `client/scripts/build-app.sh` rồi cài như thường lệ. Việc đo trong môi trường dựng đã chạy trên micro thật (tai nghe Ulisten B1 ANC, micro MacBook), nhưng các ca dưới đây cần thao tác vật lý nên không tự động hoá được.

**M1. Chọn một micro cụ thể rồi đọc chính tả nhiều lượt (ca tái hiện lỗi)**
1. Cài đặt › Chung › Micro: chọn đúng tên tai nghe đang dùng (không để "Mặc định hệ thống"). Giữ ⌥ trái, nói một câu, nhả — lặp 10 lượt liên tiếp.
   **KỲ VỌNG:** cả 10 lượt ra chữ; KHÔNG lần nào hiện đỏ "thiết bị micro thay đổi hoặc bị rút"; thẻ "Lỗi gần nhất"/"Có vấn đề cần xử lý" ở Tổng quan không xuất hiện.
   **DẤU HIỆU SAI:** thanh đỏ + mất chữ ở lượt bất kỳ khi KHÔNG hề rút/đổi gì.

**M2. Rút/tắt tai nghe Bluetooth GIỮA câu (đang chọn đúng tai nghe đó)**
1. Chọn tai nghe Bluetooth ở Cài đặt. Giữ ⌥ trái, nói liền khoảng 4–5 giây, trong lúc đang nói TẮT tai nghe (hoặc đưa ra xa tới khi ngắt), vẫn giữ ⌥, nói thêm 2 giây rồi nhả.
   **KỲ VỌNG:** KHÔNG có thanh đỏ; vflow vẫn ghi tiếp bằng micro mặc định của máy (micro MacBook), chữ của CẢ câu (kể cả phần trước lúc tắt tai nghe) được gửi đi; HUD hiện MỘT lần nhắc nhẹ "Micro đã chọn không còn — dùng micro mặc định"; Cài đặt › Chung › Micro tự về "Mặc định hệ thống" nếu tai nghe thật sự không còn trong danh sách.
   **DẤU HIỆU SAI:** thanh đỏ "Micro không dùng được…"; mất phần đã nói trước lúc tắt; nhắc lặp lại ở lượt sau.
2. Lặp lại nhưng tắt tai nghe NGAY khi vừa bấm ⌥ (chưa kịp nói gì), rồi nói bằng micro máy.
   **KỲ VỌNG:** nếu không thu được gì thì (và chỉ khi đó) mới hiện đỏ, với thông điệp ĐÚNG: "Micro không dùng được: micro bị ngắt giữa chừng (tên thiết bị)" hoặc "không mở được micro (…)", KHÔNG phải câu cũ "thiết bị micro thay đổi hoặc bị rút".

**M3. App khác chiếm/nhả micro (Zoom/Meet/FaceTime) trong lúc đọc chính tả**
1. Mở cuộc họp (Meet/Zoom) có bật micro, rồi giữ ⌥ trái nói một câu ở vflow; thử cả khi bật/tắt micro trong cuộc họp giữa lúc đang nói.
   **KỲ VỌNG:** không thanh đỏ; chữ ra bình thường (nếu hệ thống tạm giữ micro khiến vflow không nhận được tiếng thì vflow tự dựng lại, tối đa vài giây).
   **DẤU HIỆU SAI:** thanh đỏ chỉ vì cuộc họp đổi trạng thái micro.

**M4. Đổi tai nghe Bluetooth sang chế độ gọi (HFP) ↔ nghe nhạc (A2DP) trong lúc giữ ⌥**
1. Đang nghe nhạc bằng tai nghe Bluetooth (micro mặc định là tai nghe), giữ ⌥ trái nói một câu 5–6 giây.
   **KỲ VỌNG:** chữ ra đủ câu dù hệ thống đổi tuyến âm thanh/tần số lấy mẫu giữa chừng; không thanh đỏ.

**M5. Thẻ "Lỗi gần nhất" tự hết**
1. (Tạo lỗi: tắt quyền Micro ở System Settings, giữ ⌥ để thấy lỗi, bật lại quyền.) Sau đó đọc chính tả MỘT lượt thành công.
   **KỲ VỌNG:** ngay sau lượt thành công thẻ "Lỗi gần nhất" và "Có vấn đề cần xử lý" biến mất, KHÔNG cần bấm X.

## N. O1: bản KHÔNG kèm model (công khai) — bản chủ dự án đang dùng KHÔNG được đổi trải nghiệm

Dựng: `client/scripts/build-app.sh --no-model` (≈ 146 MB; bản mặc định `build-app.sh` không cờ vẫn ≈ 179 MB, KÈM model). Chạy bản mới bằng `open client/build/VFlow.app` — KHÔNG thoát/đè bản đang chạy ở `/Applications` nếu chưa muốn. Các bước 1–2 đã được tự động kiểm bằng thư mục tạm (xem báo cáo O1); bước 3–6 cần cửa sổ thật nên CHỈ chủ dự án kiểm được.

**N1. Máy đã có model ở `~/.vflow/models/zipformer-vi-30m` (đúng máy của anh)**
1. Mở bản không kèm model.
   **KỲ VỌNG:** mở ngay như bản kèm model, KHÔNG có cửa sổ "Cần tải model…", không tải gì, không chậm hơn thấy được; giữ ⌥ nói bình thường.
   **DẤU HIỆU SAI:** hiện màn hình xin tải hoặc xin đồng ý giấy phép; Tổng quan › Hệ thống báo thiếu model.

**N2. Máy CHƯA có model (thử an toàn bằng thư mục khác, KHÔNG xoá `~/.vflow` thật)**
1. Thoát bản đang thử, rồi chạy: `VFLOW_HOME=/tmp/vflow-thu ./client/build/VFlow.app/Contents/MacOS/VFlow` (thư mục tạm; có thể tạo `/tmp/vflow-thu/client.json` = `{"port": 28999}` để không đụng cổng 7611 của bản đang dùng).
   **KỲ VỌNG:** hiện cửa sổ **"Tải model nhận dạng giọng nói"** có: tên model (Zipformer-30M-RNNT-6000h), dung lượng (≈ 26 MB tải / ≈ 33 MB trên đĩa), nguồn (Hugging Face + GitHub k2-fsa/sherpa-onnx), giấy phép **CC-BY-NC-ND-4.0** với câu "Chỉ dùng cá nhân, phi thương mại; không được phát hành lại bản sửa đổi", hai nút "Mở trang giấy phép"/"Mở trang model" (mở trình duyệt), nút "Để sau" và "Đồng ý và tải (≈ 26 MB)". Chưa bấm đồng ý thì KHÔNG có tải nào (Activity Monitor › Mạng không thấy tăng).
2. Bấm "Để sau", rồi mở Tổng quan › Hệ thống.
   **KỲ VỌNG:** dòng "Chưa có model nhận dạng giọng nói — cần tải một lần…" và nút **"Tải model…"** mở lại cửa sổ.
3. Bấm "Đồng ý và tải", xem thanh tiến độ ("Đã tải X / 25,2 MB"), rồi bấm "Huỷ tải" giữa chừng.
   **KỲ VỌNG:** dừng ngay, hiện "Đã huỷ tải…" và nút "Thử lại"; không còn thư mục `.tmp-zipformer-vi-30m.*` trong `/tmp/vflow-thu/models`.
4. Bấm "Thử lại" và để tải xong.
   **KỲ VỌNG:** "Đang kiểm mã băm SHA-256…" rồi "Đã tải xong và kiểm mã băm khớp"; engine tự khởi động lại; giữ ⌥ nói ra chữ. `ls /tmp/vflow-thu/models/zipformer-vi-30m` có `encoder.int8.onnx decoder.onnx joiner.int8.onnx tokens.txt manifest.json` và `shasum -a 256` các tệp khớp `~/.vflow/models/zipformer-vi-30m` (cùng gói gốc).
5. Tắt mạng (Wi-Fi off) rồi bấm "Thử lại" ở một thư mục trống khác.
   **KỲ VỌNG:** lỗi đỏ "Không tải được model — lỗi mạng hoặc máy chủ…", nút "Thử lại" dùng được khi bật lại mạng; KHÔNG để lại model dở dang.
6. (Chỉ để xem) làm hỏng một tệp model đã tải (`echo x >> .../encoder.int8.onnx`) rồi mở lại app.
   **KỲ VỌNG:** vẫn coi là "đủ" (lúc mở chỉ kiểm sự có mặt của tệp, không băm 33 MB mỗi lần — đây là chủ ý để không chậm); mã băm chỉ được kiểm ngay sau khi TẢI. Nếu muốn kiểm tay: `node bin/vflow.js doctor`.

## O. V4/V5: chế độ Dịch (gửi chữ qua máy chủ LLM của bạn, không gửi âm thanh)

Cần `cloud_llm` đang BẬT và một model LLM thật đã cấu hình (Cài đặt › Nâng cao) — không có, các bước dưới vẫn chạy được NHƯNG kết quả dịch sẽ là lỗi (`no_model`/`no_key`), chỉ kiểm được phần vô hiệu hoá/giao diện (bước O4–O6).

**O1. Nói tiếng Việt, nghe lại bằng tiếng Anh**
1. Tổng quan (hoặc menu thanh trạng thái) › chọn chế độ **Dịch**. Ô "Ngôn ngữ đích" chọn "Tiếng Anh", mức trang trọng để "Trung lập".
2. Mở TextEdit/Notes, giữ ⌥ trái, nói một câu tiếng Việt bình thường (vd. "Chiều nay tôi có cuộc họp với khách hàng"), nhả phím.
   **KỲ VỌNG:** thanh trạng thái hiện "Dịch → Tiếng Anh" trong lúc ghi (KHÁC "Đang nghe" của các chế độ khác), rồi "Đang dịch", rồi "Xong"; câu tiếng Anh (không phải tiếng Việt, không phải lời dẫn kiểu "Here is the translation:") được dán vào đúng vị trí con trỏ.
   **DẤU HIỆU SAI:** dán nguyên câu tiếng Việt; dán kèm lời dẫn; dán chuỗi rỗng mà không báo lỗi gì.
3. Đổi "Ngôn ngữ đích" sang "Tiếng Nhật", lặp lại bước 2 với câu khác.
   **KỲ VỌNG:** lần này ra tiếng Nhật, không phải tiếng Anh còn sót từ lần trước (ngôn ngữ đích đổi NGAY, không cần khởi động lại).

**O2. Dịch lại một câu trong Lịch sử**
1. Tab **Lịch sử**, chuột phải vào một câu tiếng Việt bất kỳ (của chế độ khác, không cần phải là câu Dịch) › **"Dịch câu này…"**.
   **KỲ VỌNG:** sheet "Dịch câu này" hiện ra với đúng nguyên văn câu đã chọn, ô chọn ngôn ngữ đích (mặc định theo Cài đặt hiện tại) + mức trang trọng, nút "Dịch".
2. Đổi ngôn ngữ đích sang một ngôn ngữ khác rồi bấm "Dịch".
   **KỲ VỌNG:** vài giây sau hiện bản dịch trong khung chữ, nút "Sao chép"/"Chèn vào ô đang gõ" bật lên.
3. Bấm "Dịch" LẦN NỮA ngay khi vừa đổi "Mức trang trọng" (trước khi lần đầu kịp trả lời) — bấm NHIỀU LẦN liên tiếp nhanh.
   **KỲ VỌNG:** chỉ MỘT kết quả cuối cùng hiện ra (đúng của lần bấm SAU CÙNG, không phải một kết quả cũ "trồi lên" muộn); không crash, không hiện hai kết quả chồng nhau.
4. Bấm "Huỷ" ngay sau khi bấm "Dịch" (trong lúc còn đang chờ).
   **KỲ VỌNG:** sheet đóng ngay, không có kết quả nào "trồi lên" sau khi đã đóng (không có thông báo lỗi/kết quả mồ côi xuất hiện sau khi sheet đã tắt).
5. Bấm "Chèn vào ô đang gõ" (ở bất kỳ câu dịch nào) khi đang focus vào Notes.
   **KỲ VỌNG:** đúng bản dịch được dán vào Notes, câu GỐC trong Lịch sử KHÔNG đổi (sheet không sửa lịch sử, chỉ đọc).

**O3. Đổi ngôn ngữ đích cho dictation (không qua Lịch sử)**
1. Ở chế độ Dịch (Tổng quan), đổi "Ngôn ngữ đích" sang "Tiếng Hàn", mở Cài đặt (⌘,) › Giọng nói, quay lại Tổng quan.
   **KỲ VỌNG:** vẫn còn "Tiếng Hàn" (không rơi về mặc định "Tiếng Anh" khi mở/đóng Cài đặt).
2. Chọn "Khác…" trong ô Ngôn ngữ đích, gõ `th` (Thái — không có trong danh sách cố định) rồi nhấn Enter.
   **KỲ VỌNG:** nhận mã `th`, lần dịch tiếp theo ra tiếng Thái.
3. Thử gõ `english` (chữ, không phải mã ISO) hoặc `en-US` (có tiểu thẻ vùng) vào ô "Khác…".
   **KỲ VỌNG:** KHÔNG được lưu (không đổi ngôn ngữ đích hiện tại) — cả hai đều không phải mã ISO 2–3 chữ hợp lệ theo đúng mẫu engine chấp nhận.

**O4. `cloud_llm` tắt ⇒ Dịch vô hiệu hoá hẳn**
1. Cài đặt › Nâng cao: tắt "Cho phép gửi chữ qua máy chủ của bạn" (`cloud_llm`). Quay lại Tổng quan.
   **KỲ VỌNG:** ô "Dịch" trong lưới chế độ chuyển mờ/không bấm được (không chỉ cảnh báo sau khi chọn); banner "Dịch cần gửi chữ qua máy chủ của bạn. Đám mây đang tắt." hiện kèm nút "Mở Cài đặt". Mở menu thanh trạng thái/Dock: mục "Dịch" cũng bị vô hiệu hoá (tooltip nêu lý do), có thêm mục "Bật dịch ở Cài đặt…".
   **DẤU HIỆU SAI:** vẫn chọn được Dịch rồi mới báo lỗi SAU khi đã ghi âm xong (phải chặn NGAY, không để ghi âm vô ích).
2. Nếu app ĐANG ở chế độ Dịch từ trước khi tắt đám mây: thử giữ ⌥ nói.
   **KỲ VỌNG:** không có gì được dán (không phải bản tiếng Việt gốc, không phải chuỗi rỗng) — lỗi rõ ràng, không "thành công giả".
3. Bật lại `cloud_llm`.
   **KỲ VỌNG:** Dịch chọn được lại ngay, banner biến mất.

**O5. Chỉ model đa ngôn ngữ mới cho đổi "Ngôn ngữ khi nói"**
1. Cài đặt › Giọng nói, xem mục "Ngôn ngữ khi nói" (đầu mục, trước "Lệnh dấu câu bằng giọng").
   **KỲ VỌNG (model mặc định `zipformer-vi-30m`, chỉ tiếng Việt):** "Tiếng Việt" chọn được, "Tiếng Anh" và "Tự nhận biết" MỜ/không bấm được, kèm dòng chữ cam "Model hiện tại chỉ nhận tiếng Việt — đổi model ở Cài đặt › Nâng cao" và nút "Mở màn hình chọn model…" ngay dưới.
2. Bấm "Mở màn hình chọn model…" (hoặc Cài đặt › Nâng cao › "Chọn model…"), tải và chọn một model đa ngôn ngữ (xem mục P bên dưới để biết chi tiết từng bước), quay lại mục Giọng nói.
   **KỲ VỌNG:** "Tiếng Anh"/"Tự nhận biết" giờ chọn được (theo đúng `languages`/`auto_detect` model đó báo ở `/healthz`), dòng chữ cam và nút "Mở màn hình chọn model…" biến mất.

**O6. Chữ trong giao diện không nói sai "chỉ chạy trong máy" khi Dịch đang bật**
1. Với Dịch đang chọn, xem lại nhãn ở Tổng quan/menu thanh trạng thái cho MỖI chế độ.
   **KỲ VỌNG:** Dịch luôn mang nhãn "Gửi chữ qua máy chủ của bạn" (không bao giờ "Trong máy"); các chế độ Thường/Làm sạch/Lập trình/Tự động vẫn đúng "Trong máy" dù Dịch đang được chọn (không bị "lây" nhãn sai).

## P. F2: màn hình chọn model nhận dạng giọng nói (đa ngôn ngữ)

**Bối cảnh (đọc trước):** `zipformer-vi-30m` (mặc định) chỉ hiểu tiếng Việt, rất nhẹ/nhanh (~270 MB
RAM, ~0,1 s/câu), giấy phép CC-BY-NC-ND-4.0 (chỉ dùng cá nhân). Các model Whisper (tải thêm) hiểu
được tiếng Anh/đa ngôn ngữ nhưng nặng hơn nhiều và giấy phép MIT. **Mọi số đo dưới đây lấy từ
`eval/reports/2026-10-30-multilingual.md`, đo bằng GIỌNG TỔNG HỢP (`say` của macOS) — CHƯA phải
giọng của anh.** Model `whisper-small-multilingual` MỚI được engine hỗ trợ tải từ 2026-10-31 (610 MB,
WER đo được: tiếng Việt thuần 9,6%, tiếng Anh thuần 2,5%, Việt xen Anh 50,0%, RAM đỉnh ~1 GB, RTF
trung vị 0,32 — chậm hơn hẳn zipformer nhưng hiểu được tiếng Anh, điều zipformer không làm được).

**P1. Mở màn hình chọn model**
1. Cài đặt (⌘,) › Nâng cao, xem mục "Model nhận dạng giọng nói" ở đầu trang.
   **KỲ VỌNG:** dòng "Đang dùng: Mặc định của engine" (nếu chưa từng đổi model) + nút "Chọn model…".
2. Bấm "Chọn model…".
   **KỲ VỌNG:** cửa sổ "Chọn model nhận dạng giọng nói" hiện danh sách MỌI model engine biết (không chỉ model mặc định): `zipformer-vi-30m` (Sẵn sàng, "Dùng model này"), các model khác (Chưa tải, nút "Tải…") — mỗi model có dòng đánh đổi ngắn (vd "Chỉ tiếng Việt · nhanh nhất · 33 MB · chỉ dùng cá nhân") VÀ một dòng nhỏ nhắc "Đo bằng giọng tổng hợp…" ngay dưới.

**P2. Tải `whisper-small-multilingual`**
1. Ở dòng "Whisper small đa ngôn ngữ", bấm "Tải…".
   **KỲ VỌNG:** thẻ xin đồng ý hiện ra: dung lượng "610 MB", giấy phép "MIT", tóm tắt "dùng thương mại được", nút "Mở trang giấy phép" (mở trình duyệt tới trang LICENSE của openai/whisper), nút "Đồng ý và tải" + "Huỷ". CHƯA bấm đồng ý thì Activity Monitor › Mạng không thấy tăng.
2. Bấm "Đồng ý và tải".
   **KỲ VỌNG:** thanh tiến độ "Đã tải X / … MB" cập nhật dần; nút "Tải…" ở MỌI model khác bị mờ/khoá trong lúc này (chỉ một lượt tải cùng lúc); bấm "Huỷ tải" giữa chừng thì dừng ngay, không để lại thư mục `.tmp-whisper-small-multilingual.*` trong `~/.vflow/models`.
3. Bấm lại "Tải…" (hoặc "Thử lại") và để tải xong (610 MB — có thể vài phút tuỳ mạng).
   **KỲ VỌNG:** "Đang kiểm mã băm SHA-256…" rồi dòng trạng thái đổi thành "Đã tải, chưa nạp"/"Sẵn sàng", nút đổi thành "Dùng model này".
4. Tắt mạng rồi bấm "Tải…" ở một model khác chưa tải.
   **KỲ VỌNG:** lỗi đỏ rõ ràng ("lỗi mạng hoặc máy chủ…"), nút "Thử lại" dùng được khi bật mạng lại — không "thành công giả", không đứng hình vô thời hạn.

**P3. Đổi sang model vừa tải, so sánh với model cũ**
1. Bấm "Dùng model này" ở dòng `whisper-small-multilingual`.
   **KỲ VỌNG:** nút đổi thành "Đang nạp…" vài trăm ms tới vài giây (model ~1 GB RAM, nạp chậm hơn zipformer rõ rệt — đây là "việc nặng" nêu trong mô tả tính năng), rồi dòng đó hiện huy hiệu "Đang dùng"; không đứng hình/treo cửa sổ.
2. Mở TextEdit/Notes, giữ ⌥ trái, **nói một câu tiếng Anh thuần** (vd. "Please send the final report before the meeting tomorrow morning"), nhả phím.
   **KỲ VỌNG:** chữ tiếng Anh được dán ra (đúng hoặc gần đúng câu đã nói) — ĐÂY LÀ ĐIỀU `zipformer-vi-30m` KHÔNG LÀM ĐƯỢC (thử lại với model cũ ở bước 5 để thấy khác biệt: zipformer sẽ phiên âm thành chữ Việt vô nghĩa, ví dụ kiểu "cờ lít sờ en thờ phai no report...").
3. Nói **một câu tiếng Việt xen tiếng Anh** (vd. "deploy lên staging sau khi test xong", hoặc "anh review giúp em cái commit này").
   **KỲ VỌNG:** nghe được phần lớn câu đúng (có thể vẫn sai vài từ — báo cáo đo cho WER nhóm này ~50%, KHÔNG hoàn hảo, đừng kỳ vọng tuyệt đối đúng). So khớp bằng mắt với báo cáo `eval/reports/2026-10-30-multilingual.md` mục "Ví dụ văn bản THẬT" nếu muốn đối chiếu.
4. Cài đặt › Giọng nói: xem mục "Ngôn ngữ khi nói".
   **KỲ VỌNG:** "Tiếng Anh"/"Tự nhận biết" giờ CHỌN ĐƯỢC (không còn mờ); nếu model đang dùng là họ Whisper, thấy thêm dòng chữ nhỏ cảnh báo: "Từ điển cá nhân (phiên âm) có thể kém hiệu quả hơn với model Whisper…" — đây là thật, không phải doạ suông (đo được 2/36 câu đúng với zipformer, 0/36 với Whisper).
5. Quay lại màn hình chọn model, bấm "Dùng model này" ở `zipformer-vi-30m` để đổi về model cũ, lặp lại bước 2 (câu tiếng Anh) để SO SÁNH trực tiếp.
   **KỲ VỌNG:** cùng một câu tiếng Anh, zipformer ra chữ vô nghĩa/phiên âm kiểu Việt; whisper-small-multilingual (bước 2) ra đúng tiếng Anh — thấy rõ đánh đổi "chậm hơn nhưng hiểu được tiếng Anh" bằng chính tai mình, không chỉ qua số liệu.

**P4. Không cho xoá model đang dùng; xoá giải phóng đĩa**
1. Với `zipformer-vi-30m` đang được chọn (từ P3 bước 5), mở màn hình chọn model.
   **KỲ VỌNG:** dòng `zipformer-vi-30m` KHÔNG có nút "Xoá…" (đang dùng); dòng `whisper-small-multilingual` (đã tải, không đang dùng) CÓ nút "Xoá…".
2. Bấm "Xoá…" ở `whisper-small-multilingual`.
   **KỲ VỌNG:** hộp thoại xác nhận "Xoá model đã tải?" hiện ra trước khi xoá thật; xác nhận xong thì dòng đó đổi lại thành "Chưa tải"/"Tải…"; `~/.vflow/models/whisper-small-multilingual` không còn trên đĩa (`ls ~/.vflow/models`).
3. (Dọn dẹp) nếu không muốn giữ model đã tải thử, lặp lại để xoá các model Whisper khác đã tải trong lúc kiểm tay ở trên.
