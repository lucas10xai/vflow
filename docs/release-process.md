# Quy trình phát hành vflow

Phát hành qua **GitHub Releases**: gắn thẻ `vX.Y.Z` ⇒ workflow `.github/workflows/release.yml` chạy test, dựng `VFlow.app` **không kèm model**, nén zip, tạo SHA-256 và tạo Release. Bản dựng **ký ad-hoc, chưa công chứng** (chưa mua Apple Developer Program) — người dùng phải tự gỡ chặn macOS (hướng dẫn nằm trong `README.md` và được tự chèn vào ghi chú phát hành).

Không có bí mật ký nào trong CI: chỉ dùng `GITHUB_TOKEN` tự cấp của GitHub Actions để tạo Release.

## 1. Đánh số phiên bản

[SemVer](https://semver.org/lang/vi/) `MAJOR.MINOR.PATCH`, có thể thêm hậu tố tiền phát hành `-rc.1`, `-beta.1`:

- **PATCH** (0.1.0 → 0.1.1): sửa lỗi, không đổi hành vi dùng hằng ngày.
- **MINOR** (0.1.x → 0.2.0): tính năng mới; **khi còn `0.x`, MINOR được phép đổi cách dùng** (ghi rõ ở mục "Thay đổi gây gián đoạn" của CHANGELOG).
- **MAJOR** (→ 1.0.0): khi coi API/cách dùng đã ổn định.
- Thẻ có hậu tố (`v0.2.0-rc.1`) tự được đánh dấu **pre-release** trên GitHub.

Số phiên bản nằm ở **hai nơi workflow bắt buộc khớp với thẻ** (không khớp ⇒ workflow dừng, không đăng):

| Nơi | Chỗ sửa |
|---|---|
| Engine (hiện ở `/healthz`, chẩn đoán) | `engine/server/index.js` — `export const VERSION = '…'` |
| App macOS (Info.plist, hiện ở Cài đặt › Nâng cao) | `client/scripts/build-app.sh` — `CFBundleShortVersionString` |

Lưu ý: `package.json` đang ghi `"version": "0.0.0"` (gói `private`) và `CFBundleVersion` trong `build-app.sh` đang cố định `1`; workflow **không** kiểm hai giá trị này. Nên đồng bộ `package.json` cho đỡ nhầm; `CFBundleVersion` chỉ quan trọng nếu sau này dùng cập nhật tự động.

## 2. Viết ghi chú phát hành

Ghi chú lấy từ `CHANGELOG.md`. Trước khi gắn thẻ:

1. Đổi tiêu đề mục `## [Chưa phát hành]` thành `## [X.Y.Z] - YYYY-MM-DD` (giữ **đúng dạng** `## [X.Y.Z]` — workflow cắt mục theo tiêu đề này, thiếu mục ⇒ workflow dừng), rồi thêm mục `## [Chưa phát hành]` trống phía trên.
2. Viết cho người dùng, không cho lập trình viên: họ thấy gì khác, có gì phải làm lại (ví dụ cấp lại quyền), có gì gây gián đoạn, hạn chế đã biết. Nhóm theo `### Thêm`, `### Đổi`, `### Sửa`, `### Gây gián đoạn`, `### Đã biết`.
3. Không bịa: chỉ liệt kê điều thật sự có trong `git log vA..HEAD`; mỗi mục nên truy được tới một commit.
4. Phần chân ghi chú (cách gỡ chặn, model không kèm, riêng tư) lấy tự động từ `.github/RELEASE_NOTES_FOOTER.md` — sửa ở đó nếu nội dung đó đổi.

## 3. Kiểm trước khi phát hành (checklist)

Chạy trên Mac Apple Silicon, ở nhánh `main` sạch, đã commit mọi thứ:

- [ ] `npm ci && npm test` xanh.
- [ ] `(cd client && swift test)` xanh.
- [ ] Số phiên bản đã khớp ở cả hai nơi (mục 1) và `CHANGELOG.md` đã có mục `[X.Y.Z]`.
- [ ] Dựng bản công khai và kiểm **không có model** trong gói:
  ```sh
  client/scripts/build-app.sh --no-model
  find client/build/VFlow.app \( -name '*.onnx' -o -path '*/Resources/models/*' \) -print   # phải RỖNG
  lipo -archs client/build/VFlow.app/Contents/MacOS/VFlow                                    # phải là: arm64
  codesign --verify --deep --strict client/build/VFlow.app
  ```
- [ ] **Giấy phép:** `NOTICE` còn đúng — chạy `npm ls --all` và so với `package-lock.json`; nếu có phụ thuộc mới/đổi phiên bản, kiểm giấy phép của nó theo `docs/license-decision.md` mục 5 và cập nhật `NOTICE`. Kiểm lại giấy phép model trên Hugging Face (`https://huggingface.co/api/models/hynt/Zipformer-30M-RNNT-6000h` ⇒ trường `license`).
- [ ] **Không lộ riêng tư:** quét repo tìm bí mật và dữ liệu cá nhân trước khi công khai/gắn thẻ:
  ```sh
  git ls-files | xargs grep -InE 'sk-[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH|PRIVATE)|/Users/[a-z]+|100\.[0-9]+\.[0-9]+\.[0-9]+' | head
  git ls-files | grep -iE '\.(wav|onnx|pcm|pyc)$|(^|/)\.env'                                  # phải RỖNG
  ```
  (Kết quả không rỗng không tự động là lỗi — xem từng dòng — nhưng phải xử lý có chủ đích.)
- [ ] **Chạy thử workflow:** GitHub › Actions › "Phát hành" › *Run workflow* (để `dry_run` bật). Phải xanh toàn bộ, rồi tải zip ở mục *Artifacts* về kiểm.
- [ ] **Kiểm tay trên máy sạch** (tài khoản macOS mới hoặc Mac khác, chưa có `~/.vflow`): tải zip **bằng trình duyệt** (để có nhãn quarantine thật) ⇒ làm đúng hướng dẫn gỡ chặn trong README ⇒ cấp 3 quyền ⇒ cửa sổ tải model hiện và tải xong ⇒ đọc chính tả một câu vào Terminal và một ô văn bản. Theo `client/MANUAL-TEST.md`.
- [ ] Đối chiếu `shasum -a 256 -c` với tệp `.sha256` của bản dry-run.

## 4. Gắn thẻ và phát hành

```sh
git switch main && git pull --ff-only
git tag -a vX.Y.Z -m "vflow X.Y.Z"
git push origin vX.Y.Z
```

Workflow tự chạy, mất khoảng một lúc (swift test + dựng release trên runner macOS). Theo dõi ở tab Actions. Thành công ⇒ Release xuất hiện với zip + `.sha256` + ghi chú.

**Thẻ sai / phát hành hỏng:** không dời thẻ. Xoá Release và thẻ (`gh release delete vX.Y.Z --cleanup-tag`), sửa lỗi, rồi gắn thẻ lại — hoặc tốt hơn: phát hành `X.Y.(Z+1)`. Nếu bản hỏng đã bị người dùng tải, ghi vào CHANGELOG của bản kế tiếp.

## 5. Sau khi phát hành

- [ ] Mở trang Release: có đúng 2 tệp (zip, `.sha256`), ghi chú hiển thị đúng, đánh dấu pre-release nếu có hậu tố.
- [ ] Tải zip từ Release, kiểm `shasum -a 256 -c`, giải nén, mở (theo hướng dẫn gỡ chặn) — xác nhận chạy được và **không** có model trong gói.
- [ ] Cập nhật `CHANGELOG.md` (mục `[Chưa phát hành]` đã trống) và README nếu liên kết/chữ thay đổi.
- [ ] Nếu có Homebrew tap riêng (mục 6): cập nhật `version` và `sha256` trong cask.

## 6. Đường tới Homebrew

Chưa làm. Chuẩn bị sẵn để sau này thêm được mà không phải đổi quy trình:

- Tên tệp phát hành cố định `vflow-<phiên bản>-macos-arm64.zip`, kèm `.sha256` — đủ để viết cask. Zip chứa `VFlow.app` ở gốc.
- **Tap riêng (khả thi ngay):** tạo repo `homebrew-vflow` với `Casks/vflow.rb`, mẫu (chưa kiểm bằng `brew audit`, phải chạy thử khi làm thật):
  ```ruby
  cask "vflow" do
    version "X.Y.Z"
    sha256 "<nội dung tệp .sha256>"
    url "https://github.com/<chủ>/<repo>/releases/download/v#{version}/vflow-#{version}-macos-arm64.zip"
    name "vflow"
    desc "Đọc chính tả tiếng Việt chạy hoàn toàn trong máy"
    homepage "https://github.com/<chủ>/<repo>"
    depends_on arch: :arm64
    depends_on macos: ">= :sonoma"
    app "VFlow.app"
    zap trash: ["~/.vflow"]   # CÂN NHẮC: lệnh zap xoá cả dữ liệu/lịch sử của người dùng
  end
  ```
  Người dùng cài bằng `brew tap <chủ>/vflow && brew install --cask vflow`. Homebrew gắn quarantine cho bản tải về nên **vẫn bị Gatekeeper chặn** như tải tay — cần ghi chú (`caveats`) hướng dẫn gỡ chặn; không nên tự động chạy `xattr` thay người dùng.
- **Cask chính thức (`homebrew/cask`):** theo thảo luận của Homebrew (<https://github.com/orgs/Homebrew/discussions/6482>, <https://github.com/orgs/Homebrew/discussions/7050>), cask không qua Gatekeeper (không ký Developer ID + công chứng) bị vô hiệu hoá từ 2026-09-01. Vì vậy **không thể vào cask chính thức nếu chưa mua Apple Developer Program và công chứng app** — tap riêng là đường duy nhất cho tới lúc đó. Tự kiểm lại chính sách hiện hành trước khi gửi.
- Nếu sau này mua chứng chỉ: thêm bước ký Developer ID + `notarytool` vào workflow bằng *GitHub Secrets* của chủ dự án (chưa có), bỏ phần hướng dẫn gỡ chặn khỏi README và `RELEASE_NOTES_FOOTER.md`.

## 7. Phần chưa được kiểm chứng

Workflow `release.yml` **chưa từng chạy trên GitHub Actions** khi viết (không có runner ở môi trường soạn): mới kiểm cú pháp YAML, `bash -n` từng bước, và chạy riêng các đoạn trích phiên bản/CHANGELOG/regex thẻ trên máy cục bộ. Những điều chỉ biết được khi chạy thật: `swift test` có chạy được trên runner không đầu (một số test dựng cửa sổ AppKit ngoài màn hình), Xcode mặc định của `macos-latest` có đủ Swift 6 không (workflow dừng với thông báo rõ nếu không), thời gian chạy, và quyền tạo Release bằng `GITHUB_TOKEN` (cần *Settings › Actions › General › Workflow permissions* cho phép ghi nếu repo/tổ chức mặc định chỉ đọc — workflow đã khai `permissions: contents: write`). Hãy chạy **dry-run** (mục 3) trước thẻ đầu tiên.
