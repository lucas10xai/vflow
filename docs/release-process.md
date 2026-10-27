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
- [ ] `(cd client && swift test)` xanh (máy dev: Swift 6.4 / Xcode 27; runner: Swift 6.3.3 — xem mục 7, KHÔNG thay được dry-run).
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
- [ ] **Chạy thử workflow:** GitHub › Actions › "Phát hành" › *Run workflow* (để `dry_run` bật) hoặc `gh workflow run "Phát hành" --ref main -f dry_run=true` (chi tiết ở mục 7). Phải xanh toàn bộ, rồi tải zip ở mục *Artifacts* về kiểm. Bước này CÀNG QUAN TRỌNG vì runner dùng Swift cũ hơn máy dev (mục 7): lỗi biên dịch riêng của Swift cũ chỉ lộ ở đây.
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

## 7. Môi trường runner, và điều đã/chưa được kiểm chứng

**Đã kiểm chứng thật** (workflow chạy dry-run XANH hoàn toàn trên GitHub Actions: https://github.com/lucas10xai/vflow/actions/runs/40462431540 — 3 phút): `npm test`, `swift test` (666 test = 653 + 13), dựng `build-app.sh --no-model`, kiểm gói (không model, arm64, ký ad-hoc, phiên bản), nén zip + SHA-256, tải Artifacts về giải nén kiểm lại.

**Runner:** `macos-latest` (image `macos-26`, Apple Silicon). Các Xcode có sẵn và Swift đi kèm (đo thật trong nhật ký run): 26.0/26.0.1 = Swift 6.2; 26.1/26.1.1 = 6.2.1; 26.2 = 6.2.3; 26.3 = 6.2.4; 26.4/26.4.1 = 6.3.1; 26.5 = 6.3.2; **26.6 (mặc định) = 6.3.3**. Không có Swift ≥ 6.4 trên image này; Swift 6.4 (= Xcode 27, cùng bản với máy dev) chỉ có ở image xem trước `xcode-27` (Xcode 27.0/27.1/27.2). Workflow tự liệt kê mọi Xcode và chọn bản có Swift cao nhất (bước "Chọn Xcode có Swift mới nhất…") — khi GitHub đưa Xcode mới vào `macos-latest` thì tự dùng bản mới.

**Lỗi trình biên dịch đã gặp (đừng sửa ngược):** run đầu tiên (https://github.com/lucas10xai/vflow/actions/runs/40461536988) thất bại vì `swift-frontend` 6.3.3 SẬP lúc IRGen khi biên dịch module `VFlow` ("SmallVector unable to grow", thunk `@isolated(any)` của `DictationMode`) — máy dev dùng Swift 6.4 nên không thấy. Nguyên nhân tìm được: truyền thẳng một hàm `@MainActor` làm tham số `set:` của `Binding(get:set:)`. Cách né (giữ nguyên hành vi): bọc closure `set: { onChange($0) }` ở `SettingsView.swift` (`ModeSection`) và `SettingsViewV2.swift` (`AppRuleRow`); chú thích tại chỗ nhắc không dọn ngược. Quy tắc cho mã mới: **KHÔNG truyền giá trị hàm `@MainActor`/non-Sendable thẳng vào tham số closure của SwiftUI (`Binding(get:set:)`, …) — bọc bằng closure literal**; và vì máy dev chạy Swift mới hơn runner, một lỗi biên dịch riêng của Swift cũ chỉ lộ ra ở dry-run — luôn chạy dry-run trước khi gắn thẻ (mục 3).

**Chưa kiểm chứng:** bước "Tạo GitHub Release" (bị bỏ qua khi dry-run, chỉ chạy khi gắn thẻ `v*`): quyền tạo Release bằng `GITHUB_TOKEN` (cần *Settings › Actions › General › Workflow permissions* cho phép ghi nếu repo/tổ chức mặc định chỉ đọc — workflow đã khai `permissions: contents: write`) và cờ `--verify-tag`/`--prerelease`. Thẻ đầu tiên là lần chạy thật đầu tiên của bước này; nên thử bằng thẻ tiền phát hành (`v0.1.0-rc.1`, cần khớp quy tắc phiên bản ở mục 1) trước.

### Cách chạy thử (dry-run)

```sh
gh workflow run "Phát hành" --ref main -f dry_run=true     # hoặc GitHub › Actions › Phát hành › Run workflow
gh run list --workflow "Phát hành" --limit 1               # lấy ID run
gh run watch <ID> --exit-status                            # theo dõi (khoảng 3 phút)
gh run download <ID> --dir /tmp/vflow-dry-run              # tải Artifacts (zip + .sha256)
cd /tmp/vflow-dry-run/vflow-*-macos-arm64 && shasum -a 256 -c *.sha256
```

Muốn thử trên runner khác mà không sửa tệp: `gh workflow run "Phát hành" --ref main -f dry_run=true -f runner=xcode-27` (đầu vào `runner`; gắn thẻ `v*` luôn dùng `macos-latest`). Dry-run KHÔNG tạo Release và KHÔNG cần/động đến bí mật nào.

Kiểm zip đã tải (ví dụ):

```sh
ditto -x -k vflow-*-macos-arm64.zip x && ls x                         # LICENSE NOTICE VFlow.app
ls x/VFlow.app/Contents/Resources/models                              # phải báo: No such file
ls x/VFlow.app/Contents/Resources/LICENSES                            # có MODEL-ZIPFORMER-VI-30M.txt…
codesign --verify --deep --strict x/VFlow.app && codesign -dv x/VFlow.app 2>&1 | grep Signature   # Signature=adhoc
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' x/VFlow.app/Contents/Info.plist
du -sh x/VFlow.app                                                    # ≈ 146M (zip nén ≈ 46 MB)
```
