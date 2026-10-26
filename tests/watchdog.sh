#!/usr/bin/env bash
# Host regression test: exercise the production supervisor with isolated paths
# and process-probe substitutes. Real /proc identity checks require Android.
set -eu
project=$(cd "$(dirname "$0")/.." && pwd)
export TEST_ROOT
TEST_ROOT=$(mktemp -d)
supervisor=''
cleanup() {
    rm -f "$TEST_ROOT/enabled"
    if [ -n "$supervisor" ]; then kill "$supervisor" 2>/dev/null || true; fi
    sleep 2
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT
sed -e 's|^D=/data/adb/frpc-android$|D="$TEST_ROOT"|' \
    -e 's|^LOCK=/dev/frpc-android.lock$|LOCK="$TEST_ROOT/lock"|' \
    "$project/android/app/src/main/assets/supervisor.sh" > "$TEST_ROOT/supervisor.sh"
cat > "$TEST_ROOT/functions.sh" <<'EOF'
child_alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
supervisor_alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
EOF
cat > "$TEST_ROOT/frpc" <<'EOF'
#!/bin/sh
echo run >> "$TEST_ROOT/starts"
if [ ! -f "$TEST_ROOT/crashed" ]; then touch "$TEST_ROOT/crashed"; sleep 1; exit 12; fi
while :; do sleep 1; done
EOF
chmod +x "$TEST_ROOT/frpc"
touch "$TEST_ROOT/enabled"
bash "$TEST_ROOT/supervisor.sh" &
supervisor=$!
for _ in $(seq 1 20); do
    [ -f "$TEST_ROOT/starts" ] && [ "$(wc -l < "$TEST_ROOT/starts")" -ge 2 ] && break
    sleep 1
done
[ "$(wc -l < "$TEST_ROOT/starts")" -eq 2 ]
grep -q '退出 (12)' "$TEST_ROOT/frpc.log"
echo 'PASS: child crash triggers automatic restart'
bash "$TEST_ROOT/supervisor.sh"
[ "$(wc -l < "$TEST_ROOT/starts")" -eq 2 ]
echo 'PASS: duplicate supervisor launch is ignored'
child_before=$(cat "$TEST_ROOT/child.pid")
kill -9 "$supervisor"
wait "$supervisor" 2>/dev/null || true
bash "$TEST_ROOT/supervisor.sh" &
supervisor=$!
sleep 5
[ "$(cat "$TEST_ROOT/child.pid")" = "$child_before" ]
[ "$(wc -l < "$TEST_ROOT/starts")" -eq 2 ]
grep -q '接管现有 frpc' "$TEST_ROOT/frpc.log"
echo 'PASS: stale lock recovered and surviving child adopted'
rm "$TEST_ROOT/enabled"
for _ in $(seq 1 10); do
    kill -0 "$supervisor" 2>/dev/null || break
    sleep 1
done
if kill -0 "$supervisor" 2>/dev/null; then echo 'FAIL: supervisor did not stop'; exit 1; fi
wait "$supervisor"
supervisor=''
[ ! -e "$TEST_ROOT/child.pid" ]
[ ! -d "$TEST_ROOT/lock" ]
sleep 4
[ "$(wc -l < "$TEST_ROOT/starts")" -eq 2 ]
echo 'PASS: explicit stop exits supervisor and prevents restart'
