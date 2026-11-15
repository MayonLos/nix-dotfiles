#!/usr/bin/env bash
# Brief verification against the *running* Mango desktop (the real eDP-1
# session). Captures, copies, and saves a screenshot, checks PNG integrity and
# the physical 2560x1600 size, opens the fullscreen editor for a few seconds
# and kills it again. Nothing is written to ~/.config; saves go to $OUT.
#
#   MS=... OUT=/tmp/real WAYLAND_DISPLAY=wayland-0 ./real-session.sh
set -uo pipefail

MS=${MS:?set MS to the mark-shot binary under test}
OUT=${OUT:-/tmp/mark-shot-real}
GRIM=${GRIM:-grim}
WL_PASTE=${WL_PASTE:-wl-paste}
MAGICK=${MAGICK:-magick}
PYTHON=${PYTHON:-python3}

mkdir -p "$OUT/shots" "$OUT/shots/save-dir"
: > "$OUT/results.txt"

fail=0
record() {
  local name=$1 status=$2 detail=$3
  printf '[%s] %s: %s\n' "$status" "$name" "$detail" | tee -a "$OUT/results.txt"
  [[ $status == PASS ]] || fail=$((fail + 1))
}
size_of() { "$MAGICK" identify -format '%wx%h' "$1" 2>/dev/null || echo BAD; }
png_check() {
  "$PYTHON" - "$1" <<'PY'
import struct, sys, zlib
data = open(sys.argv[1], 'rb').read()
assert data[:8] == b'\x89PNG\r\n\x1a\n', 'bad signature'
off = 8; idat = bytearray(); ihdr = None
while off + 8 <= len(data):
    length, kind = struct.unpack('>I4s', data[off:off + 8])
    body = data[off + 8:off + 8 + length]
    crc = struct.unpack('>I', data[off + 8 + length:off + 12 + length])[0]
    assert len(body) == length, f'truncated {kind}'
    assert crc == zlib.crc32(kind + body) & 0xffffffff, f'bad {kind} crc'
    if kind == b'IHDR':
        ihdr = struct.unpack('>II', body[:8])
    elif kind == b'IDAT':
        idat.extend(body)
    elif kind == b'IEND':
        raw = zlib.decompress(bytes(idat))
        print(f'{ihdr[0]}x{ihdr[1]} decoded={len(raw)} chunks-ok')
        sys.exit(0)
    off += 12 + length
sys.exit('missing IEND')
PY
}

$MS --list-displays > "$OUT/list-displays.json"
record "list-displays" "$( [[ -s $OUT/list-displays.json ]] && echo PASS || echo FAIL )" "$(head -c 240 "$OUT/list-displays.json")"

$MS --capture-to "$OUT/shots/capture-to.png" -m > "$OUT/capture-to.json" 2>&1
record "capture-to-size" "$( [[ $(size_of "$OUT/shots/capture-to.png") == 2560x1600 ]] && echo PASS || echo FAIL )" "$(size_of "$OUT/shots/capture-to.png")"
line=$(png_check "$OUT/shots/capture-to.png" 2>&1)
record "capture-to-integrity" "$( [[ $line == *chunks-ok* ]] && echo PASS || echo FAIL )" "$line"

$MS -m -f -t c -n > "$OUT/copy.log" 2>&1
record "copy-rc" "$( [[ $? -eq 0 ]] && echo PASS || echo FAIL )" "$(tail -c 160 "$OUT/copy.log" | tr '\n' ' ')"
"$WL_PASTE" --list-types > "$OUT/mime.txt" 2>&1
grep -q image/png "$OUT/mime.txt" && record "clipboard-mime" PASS "$(tr '\n' ',' < "$OUT/mime.txt")" || record "clipboard-mime" FAIL "$(cat "$OUT/mime.txt")"
"$WL_PASTE" --type image/png > "$OUT/shots/clipboard-immediate.png" 2>/dev/null
record "clipboard-immediate-size" "$( [[ $(size_of "$OUT/shots/clipboard-immediate.png") == 2560x1600 ]] && echo PASS || echo FAIL )" "$(size_of "$OUT/shots/clipboard-immediate.png") bytes=$(stat -c%s "$OUT/shots/clipboard-immediate.png" 2>/dev/null)"
line=$(png_check "$OUT/shots/clipboard-immediate.png" 2>&1)
record "clipboard-immediate-integrity" "$( [[ $line == *chunks-ok* ]] && echo PASS || echo FAIL )" "$line"
sleep 1
"$WL_PASTE" --type image/png > "$OUT/shots/clipboard-delayed.png" 2>/dev/null
record "clipboard-delayed-size" "$( [[ $(size_of "$OUT/shots/clipboard-delayed.png") == 2560x1600 ]] && echo PASS || echo FAIL )" "$(size_of "$OUT/shots/clipboard-delayed.png")"
line=$(png_check "$OUT/shots/clipboard-delayed.png" 2>&1)
record "clipboard-delayed-integrity" "$( [[ $line == *chunks-ok* ]] && echo PASS || echo FAIL )" "$line"

$MS -m -f -t s -n --output "$OUT/shots/save-dir" > "$OUT/save.log" 2>&1
record "save-rc" "$( [[ $? -eq 0 ]] && echo PASS || echo FAIL )" "$(tail -c 160 "$OUT/save.log" | tr '\n' ' ')"
saved=$(find "$OUT/shots/save-dir" -name '*.png' | head -1)
if [[ -n ${saved:-} ]]; then
  record "save-file" PASS "$saved"
  save_format=$("$MAGICK" identify -format '%m' "$saved" 2>/dev/null || echo BAD)
  record "save-magic" "$( [[ $save_format == PNG ]] && echo PASS || echo FAIL )" "$(size_of "$saved") format=$save_format"
  line=$(png_check "$saved" 2>&1)
  record "save-integrity" "$( [[ $line == *chunks-ok* ]] && echo PASS || echo FAIL )" "$line"
else
  record "save-file" FAIL "no file written"
fi

setsid "$MS" --fullscreen -n > "$OUT/editor.log" 2>&1 &
editor=$!
sleep 3
"$GRIM" -o eDP-1 "$OUT/shots/editor-overlay.png" 2>/dev/null
record "editor-overlay" "$( [[ -s $OUT/shots/editor-overlay.png ]] && echo PASS || echo FAIL )" "$(size_of "$OUT/shots/editor-overlay.png")"
kill -TERM -- -"$editor" 2>/dev/null
sleep 0.5
kill -KILL -- -"$editor" 2>/dev/null
pgrep -f "$MS --fullscreen" >/dev/null && record "editor-cleanup" FAIL "process still alive" || record "editor-cleanup" PASS "no leftover process"

echo
if [[ $fail -eq 0 ]]; then echo "REAL SESSION: ALL PASS"; else echo "REAL SESSION: $fail FAILED"; fi
exit "$fail"
