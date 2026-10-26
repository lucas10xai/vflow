#!/usr/bin/env bash
# hp.sh — đồng bộ repo vflow sang HP Windows và chạy lệnh ở đó (chạy từ Mac).
#
#   scripts/hp.sh status                    thông tin máy HP (không ghi gì lên HP)
#   scripts/hp.sh sync                      mirror repo -> C:\Users\example\dev\vflow
#   scripts/hp.sh run [--force] [--] CMD…   sync rồi chạy CMD trong thư mục đó, trả đúng mã thoát
#   scripts/hp.sh install [--force]         run npm install (bỏ qua nếu không có package.json)
#   scripts/hp.sh test [--force]            run npm test
#   scripts/hp.sh bench [--force] [--] CMD… như run, kèm RAM trống trước/sau và thời gian chạy
#
# Biến môi trường (tuỳ chọn):
#   VFLOW_HP_HOST          host SSH (mặc định windows-host)
#   VFLOW_HP_MIN_FREE_MB   ngưỡng RAM trống tối thiểu để chạy (mặc định 1500)
#   VFLOW_HP_NODE_OPTIONS  NODE_OPTIONS trên HP (mặc định --max-old-space-size=1536)
#
# Mã thoát của chính script: 2 sai cú pháp, 3 HP thiếu RAM, 255 lỗi SSH,
# 250 lỗi nội bộ phía HP; còn lại là mã thoát của lệnh từ xa.
#
# Mọi lệnh Windows chạy qua `powershell -NoProfile -EncodedCommand <bootstrap>`;
# bootstrap đọc script thật (base64 UTF-8) và dữ liệu từ stdin, nên không có
# vấn đề quoting của cmd.exe và không giới hạn độ dài dòng lệnh.
set -euo pipefail

HOST="${VFLOW_HP_HOST:-windows-host}"
MIN_FREE_MB="${VFLOW_HP_MIN_FREE_MB:-1500}"
NODE_OPTS="${VFLOW_HP_NODE_OPTIONS:---max-old-space-size=1536}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAB=$'\t'
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 "$HOST")

die() { local code="$1"; shift; printf 'hp.sh: %s\n' "$*" >&2; exit "$code"; }

[[ "$MIN_FREE_MB" =~ ^[0-9]+$ ]] || die 2 "VFLOW_HP_MIN_FREE_MB phải là số nguyên (MB)"

b64() { base64 | tr -d '\n'; }

# Bootstrap PowerShell: các dòng stdin bắt đầu bằng "#" là script (base64 UTF-8, cắt
# dòng 76 ký tự), các dòng còn lại là tham số. Dòng phải ngắn: một dòng stdin quá dài
# (~30 KB) làm kênh sshd/PowerShell trên Windows treo.
BOOT='$ErrorActionPreference="Stop";$ProgressPreference="SilentlyContinue";[Console]::OutputEncoding=New-Object Text.UTF8Encoding $false;$l=@($input|ForEach-Object {"$_".TrimEnd("`r")});$s=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((($l|Where-Object {$_.StartsWith("#")}|ForEach-Object {$_.Substring(1)}) -join "")));$r=@($l|Where-Object {$_ -ne "" -and -not $_.StartsWith("#")});try{& ([scriptblock]::Create($s)) @r}catch{[Console]::Error.WriteLine("hp.sh (phía HP): "+$_);exit 250};exit 0'
BOOT_ENC="$(printf '%s' "$BOOT" | iconv -f UTF-8 -t UTF-16LE | b64)"

# Phần chung cho mọi script phía HP: thư mục gốc cố định + kiểm tra đường dẫn.
PS_COMMON='
$root = "C:\Users\example\dev\vflow"
$protected = @(".git","node_modules","models",".vflow")
function Get-FreeMB {
  try { $v = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes; if ($null -ne $v) { return [int64]$v } } catch {}
  try { return [int64]([math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)) } catch {}
  return $null
}
function Test-Reparse([string]$p) {
  return ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
}
function Assert-Root {
  if ($root -ne "C:\Users\example\dev\vflow") { throw "thư mục gốc sai: $root" }
  if ((Test-Path -LiteralPath $root) -and (Test-Reparse $root)) { throw "TỪ CHỐI: $root là reparse point/junction" }
}
# Trả đường dẫn tuyệt đối an toàn cho một đường dẫn tương đối; ném lỗi nếu nằm ngoài $root.
function Resolve-Safe([string]$rel) {
  if ([string]::IsNullOrEmpty($rel) -or $rel.Contains(":") -or $rel.StartsWith("/") -or $rel.StartsWith("\")) { throw "TỪ CHỐI đường dẫn không hợp lệ: $rel" }
  $parts = @($rel -split "[\\/]")
  foreach ($p in $parts) {
    if ($p -eq "" -or $p -eq "." -or $p -eq "..") { throw "TỪ CHỐI đường dẫn không hợp lệ: $rel" }
    if ($protected -contains $p) { throw "TỪ CHỐI đụng thư mục được bảo vệ: $rel" }
  }
  $full = [IO.Path]::GetFullPath([IO.Path]::Combine($root, ($parts -join "\")))
  if (-not $full.StartsWith($root + "\", [StringComparison]::OrdinalIgnoreCase)) { throw "TỪ CHỐI thao tác ngoài ${root}: $full" }
  $cur = $root
  for ($i = 0; $i -lt $parts.Count - 1; $i++) {
    $cur = Join-Path $cur $parts[$i]
    if ((Test-Path -LiteralPath $cur) -and (Test-Reparse $cur)) { throw "TỪ CHỐI đi qua reparse point: $cur" }
  }
  return $full
}
function Dec([string]$s) { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) }
'

# remote_ps SCRIPT — chạy SCRIPT (PowerShell) trên HP; stdin của hàm = các dòng tham số.
remote_ps() {
  local script="$1"
  { printf '%s\n%s' "$PS_COMMON" "$script" | base64 -b 76 | sed 's/^/#/'; cat; } |
    "${SSH[@]}" "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $BOOT_ENC"
}

# Gọi remote_ps khi không cần dữ liệu riêng; lỗi SSH (255) báo rõ.
ssh_fail() {
  die 255 "lỗi SSH tới '$HOST' (mã $1). Kiểm tra Tailscale/HP đang bật và khoá SSH (BatchMode, không hỏi mật khẩu)."
}

# ---------------------------------------------------------------- status
PS_STATUS='
$ErrorActionPreference = "Continue"
function Find-Tool([string]$name) {
  $c = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $c) { return "không" }
  if ($c.Source -like "*\WindowsApps\*") { return "không (chỉ có lối tắt Microsoft Store: $($c.Source))" }
  return "có ($($c.Source))"
}
$node = "không có"
try { $node = (& node -v 2>$null); if (-not $node) { $node = "không xác định" } } catch { $node = "không có" }
$free = Get-FreeMB; if ($null -eq $free) { $free = "không xác định" }
$disk = "không xác định"
try { $disk = [math]::Round((Get-PSDrive -Name C -PSProvider FileSystem).Free / 1GB, 1) } catch {}
$py = Find-Tool "python"; if ($py -eq "không") { $py = Find-Tool "py" }
Write-Output ("Tên máy:          " + $env:COMPUTERNAME)
Write-Output ("Node:             " + $node)
Write-Output ("RAM trống:        " + $free + " MB")
Write-Output ("Ổ C: còn trống:   " + $disk + " GB")
Write-Output ("Python:           " + $py)
Write-Output ("ffmpeg:           " + (Find-Tool "ffmpeg"))
Write-Output ("Thư mục vflow:    " + $(if (Test-Path -LiteralPath $root) { "có ($root)" } else { "chưa có ($root)" }))
exit 0
'

cmd_status() {
  local rc=0
  remote_ps "$PS_STATUS" </dev/null || rc=$?
  [[ $rc -eq 0 ]] || { [[ $rc -eq 255 ]] && ssh_fail $rc; die "$rc" "status thất bại (mã $rc)"; }
}

# ---------------------------------------------------------------- sync
# Danh sách phía HP: "F<TAB>sha256<TAB>đường/dẫn" và "D<TAB>thư/mục"; bỏ qua cùng
# các mẫu loại trừ như phía Mac (mục bị loại trừ không bao giờ bị gửi hay bị xoá).
PS_LIST='
Assert-Root
if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
$out = New-Object Collections.Generic.List[string]
function Walk([string]$dir, [string]$rel) {
  foreach ($e in @(Get-ChildItem -LiteralPath $dir -Force)) {
    $r = if ($rel) { "$rel/$($e.Name)" } else { $e.Name }
    if ($e.PSIsContainer) {
      if ($protected -contains $e.Name) { continue }
      if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { $out.Add("S`t$r"); continue }
      $out.Add("D`t$r"); Walk $e.FullName $r
    } else {
      if ($e.Name -eq ".DS_Store" -or $e.Name -eq ".env" -or $e.Name -like ".env.*") { continue }
      if ($e.Extension -eq ".wav" -and $e.Length -gt 5242880) { continue }
      $h = (Get-FileHash -LiteralPath $e.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
      $out.Add("F`t$h`t$r")
    }
  }
}
Walk $root ""
foreach ($x in $out) { [Console]::Out.Write($x + "`n") }
exit 0
'

# Áp thay đổi: dòng "X<b64 đường dẫn>" xoá tệp, "Y<b64 thư mục>" xoá thư mục rỗng,
# "T<khúc b64>" các khúc của một tar, ghép lại rồi giải nén vào $root. Xoá trước, giải nén sau.
PS_APPLY='
Assert-Root
$nf = 0; $nd = 0
foreach ($line in $args) {
  $kind = $line.Substring(0, 1); $val = $line.Substring(1)
  if ($kind -eq "X") {
    $full = Resolve-Safe (Dec $val)
    if (Test-Path -LiteralPath $full -PathType Leaf) { Remove-Item -LiteralPath $full -Force; $nf++ }
  } elseif ($kind -eq "Y") {
    $full = Resolve-Safe (Dec $val)
    if ((Test-Path -LiteralPath $full -PathType Container) -and -not (Test-Reparse $full)) {
      if (@(Get-ChildItem -LiteralPath $full -Force).Count -eq 0) { [IO.Directory]::Delete($full, $false); $nd++ }
    }
  }
}
$tarB64 = New-Object Text.StringBuilder
foreach ($line in $args) { if ($line.Substring(0, 1) -eq "T") { [void]$tarB64.Append($line.Substring(1)) } }
if ($tarB64.Length -gt 0) {
  $bytes = [Convert]::FromBase64String($tarB64.ToString())
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = "$env:SystemRoot\System32\tar.exe"
  $psi.Arguments = "-xf - -C `"$root`""
  $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true
  $p = [Diagnostics.Process]::Start($psi)
  $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length); $p.StandardInput.Close(); $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "tar.exe giải nén lỗi (mã $($p.ExitCode))" }
}
Write-Output "HP: đã xoá $nf tệp, $nd thư mục rỗng."
exit 0
'

# Liệt kê phía Mac (đường dẫn tương đối, tách bằng NUL). Loại trừ: .git, node_modules,
# models, .vflow (ở mọi cấp), .DS_Store, .env/.env.* (tránh mang secret sang HP), *.wav > 5 MB.
local_find() { # $1 = f | d
  (cd "$REPO" && find . \( -type d \( -iname .git -o -iname node_modules -o -iname models -o -iname .vflow \) -prune \) -o \
    \( -type "$1" ! -path . ! -iname .DS_Store ! -iname .env ! -iname '.env.*' ! \( -iname '*.wav' -size +5242880c \) -print0 \))
}

cmd_sync() {
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/vflow-hp.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  # 1) Mac: sha256 + đường dẫn. shasum thêm "\" đầu dòng nếu tên có ký tự lạ -> từ chối.
  local_find f | (cd "$REPO" && xargs -0 shasum -a 256 --) >"$tmp/l.raw" || die 1 "không băm được tệp phía Mac"
  if grep -q '^\\' "$tmp/l.raw"; then die 1 "có tên tệp chứa xuống dòng/backslash, không đồng bộ được"; fi
  sed -E "s#^([0-9a-f]{64})  \\./#\\1${TAB}#" "$tmp/l.raw" | LC_ALL=C sort -t "$TAB" -k2 >"$tmp/l.files"
  if grep -q '\\' "$tmp/l.files"; then die 1 "tên tệp chứa backslash, không đồng bộ được sang Windows"; fi
  local_find d | tr '\0' '\n' | sed 's#^\./##' | LC_ALL=C sort >"$tmp/l.dirs"

  # 2) HP: danh sách hiện có.
  remote_ps "$PS_LIST" </dev/null | tr -d '\r' >"$tmp/r.raw" || rc=$?
  [[ $rc -eq 0 ]] || { [[ $rc -eq 255 ]] && ssh_fail $rc; die "$rc" "không lấy được danh sách tệp trên HP (mã $rc)"; }
  grep "^S${TAB}" "$tmp/r.raw" | cut -f2 | sed 's/^/hp.sh: CẢNH BÁO bỏ qua reparse point trên HP: /' >&2 || true
  { grep "^F${TAB}" "$tmp/r.raw" || true; } | cut -f2,3 | LC_ALL=C sort -t "$TAB" -k2 >"$tmp/r.files"
  { grep "^D${TAB}" "$tmp/r.raw" || true; } | cut -f2 | LC_ALL=C sort >"$tmp/r.dirs"

  # 3) So sánh.
  LC_ALL=C comm -23 <(LC_ALL=C sort "$tmp/l.files") <(LC_ALL=C sort "$tmp/r.files") | cut -f2 >"$tmp/send"
  LC_ALL=C comm -23 <(cut -f2 "$tmp/r.files" | LC_ALL=C sort) <(cut -f2 "$tmp/l.files" | LC_ALL=C sort) >"$tmp/del"
  # Thư mục thừa: sâu nhất trước để xoá được thư mục cha sau khi con đã rỗng.
  LC_ALL=C comm -23 "$tmp/r.dirs" "$tmp/l.dirs" | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2- >"$tmp/deld"

  local nsend ndel nddel ntotal
  nsend=$(wc -l <"$tmp/send" | tr -d ' '); ndel=$(wc -l <"$tmp/del" | tr -d ' ')
  nddel=$(wc -l <"$tmp/deld" | tr -d ' '); ntotal=$(wc -l <"$tmp/l.files" | tr -d ' ')
  if [[ $nsend -eq 0 && $ndel -eq 0 && $nddel -eq 0 ]]; then
    echo "sync: không có thay đổi ($ntotal tệp đã khớp)."
    return 0
  fi

  # 4) Gửi tar các tệp mới/đổi + danh sách xoá.
  {
    while IFS= read -r p; do printf 'X%s\n' "$(printf '%s' "$p" | b64)"; done <"$tmp/del"
    while IFS= read -r p; do printf 'Y%s\n' "$(printf '%s' "$p" | b64)"; done <"$tmp/deld"
    if [[ $nsend -gt 0 ]]; then
      (cd "$REPO" && COPYFILE_DISABLE=1 tar --no-mac-metadata -cf - -T "$tmp/send") | base64 -b 76 | sed 's/^/T/'
    fi
  } >"$tmp/payload" || die 1 "không tạo được gói tar phía Mac"
  rc=0
  remote_ps "$PS_APPLY" <"$tmp/payload" || rc=$?
  [[ $rc -eq 0 ]] || { [[ $rc -eq 255 ]] && ssh_fail $rc; die "$rc" "áp thay đổi trên HP thất bại (mã $rc)"; }
  echo "sync: gửi $nsend tệp, xoá $ndel tệp + $nddel thư mục; tổng $ntotal tệp."
}

# ---------------------------------------------------------------- run / bench
PS_FREE='Assert-Root; $f = Get-FreeMB; if ($null -eq $f) { Write-Output "unknown" } else { Write-Output $f }; exit 0'

PS_RUN='
Assert-Root
$bench = ($args[0] -eq "bench=1")
$env:NODE_OPTIONS = Dec $args[1]
$cmdline = Dec $args[2]
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "chưa có $root (sync chưa chạy?)" }
# Tiến trình con kế thừa mức ưu tiên BelowNormal của tiến trình này.
(Get-Process -Id $PID).PriorityClass = "BelowNormal"
$before = Get-FreeMB
$sw = [Diagnostics.Stopwatch]::StartNew()
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = "$env:SystemRoot\System32\cmd.exe"
$psi.Arguments = "/d /s /c `"" + $cmdline + "`""
$psi.WorkingDirectory = $root
$psi.UseShellExecute = $false
$p = [Diagnostics.Process]::Start($psi)
$p.WaitForExit()
$sw.Stop()
$code = $p.ExitCode
if ($bench) {
  $after = Get-FreeMB
  $fmt = { param($v) if ($null -eq $v) { "không xác định" } else { "$v MB" } }
  [Console]::Error.WriteLine("[bench] RAM trống trước: " + (& $fmt $before))
  [Console]::Error.WriteLine("[bench] RAM trống sau:   " + (& $fmt $after))
  [Console]::Error.WriteLine("[bench] thời gian chạy:  " + [math]::Round($sw.Elapsed.TotalSeconds, 3) + " s")
  [Console]::Error.WriteLine("[bench] mã thoát:        $code")
}
exit $code
'

# Trích một tham số theo quy tắc dòng lệnh Windows (CommandLineToArgvW / CRT).
# Tham số đã được chặn dấu " nên chỉ cần bọc ngoặc và nhân đôi \ ở cuối.
win_quote() {
  local a="$1" tail=""
  if [[ -n "$a" && "$a" =~ ^[A-Za-z0-9_./:=+,@-]+$ ]]; then printf '%s' "$a"; return; fi
  [[ "$a" =~ (\\+)$ ]] && tail="${BASH_REMATCH[1]}"
  printf '"%s%s"' "$a" "$tail"
}

check_ram() { # $1 = force (0|1)
  local free rc=0
  free="$(remote_ps "$PS_FREE" </dev/null | tr -d '\r\n')" || rc=$?
  [[ $rc -eq 0 ]] || { [[ $rc -eq 255 ]] && ssh_fail $rc; die "$rc" "không đọc được RAM trên HP (mã $rc)"; }
  if [[ ! "$free" =~ ^[0-9]+$ ]]; then
    [[ "$1" == 1 ]] && { echo "hp.sh: RAM trống trên HP không xác định; --force nên vẫn chạy." >&2; return 0; }
    die 3 "không xác định được RAM trống trên HP; từ chối chạy (dùng --force để bỏ qua)."
  fi
  if (( free < MIN_FREE_MB )); then
    [[ "$1" == 1 ]] && { echo "hp.sh: HP chỉ còn $free MB RAM trống (< $MIN_FREE_MB MB); --force nên vẫn chạy." >&2; return 0; }
    die 3 "HP chỉ còn $free MB RAM trống (< $MIN_FREE_MB MB). Từ chối chạy để các dịch vụ khác còn mượt; dùng --force nếu thật sự cần."
  fi
}

cmd_run() { # $1 = bench (0|1), rồi [--force] [--] CMD…
  local bench="$1" force=0; shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=1; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  [[ $# -gt 0 ]] || die 2 "thiếu lệnh. Dùng: hp.sh run [--force] [--] <lệnh…>"
  local cmdline="" a
  for a in "$@"; do
    # cmd.exe đếm dấu " để biết đang trong/ngoài ngoặc; \" lồng vào sẽ làm & | > lọt ra ngoài.
    [[ "$a" != *'"'* ]] || die 2 "tham số chứa dấu \" không được hỗ trợ (cmd.exe hiểu sai): $a"
    cmdline+="${cmdline:+ }$(win_quote "$a")"
  done

  check_ram "$force"
  (cmd_sync) >&2 || exit $?

  local rc=0
  remote_ps "$PS_RUN" < <(printf 'bench=%s\n%s\n%s\n' "$bench" "$(printf '%s' "$NODE_OPTS" | b64)" "$(printf '%s' "$cmdline" | b64)") || rc=$?
  if [[ $rc -eq 255 ]]; then
    echo "hp.sh: mã thoát 255 — có thể là lỗi SSH hoặc lệnh từ xa tự trả 255." >&2
  elif [[ $rc -eq 250 ]]; then
    echo "hp.sh: mã thoát 250 — lỗi nội bộ phía HP (xem thông báo ở trên)." >&2
  fi
  exit "$rc"
}

usage() { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# Cho phép `source scripts/hp.sh` (gỡ lỗi) mà không chạy lệnh con.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi

sub="${1:-}"; [[ $# -gt 0 ]] && shift
case "$sub" in
  status) cmd_status ;;
  sync) cmd_sync ;;
  run) cmd_run 0 "$@" ;;
  bench) cmd_run 1 "$@" ;;
  install)
    [[ -f "$REPO/package.json" ]] || { echo "install: không có package.json, bỏ qua."; exit 0; }
    cmd_run 0 "$@" -- npm install ;;
  test) cmd_run 0 "$@" -- npm test ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
