#!/system/bin/sh
# All state is private to root. /dev locks vanish automatically at reboot.
umask 077
D=/data/adb/frpc-android
LOCK=/dev/frpc-android.lock
cd "$D" || exit 1
. "$D/functions.sh"
if ! mkdir "$LOCK" 2>/dev/null; then
    old=$(cat "$LOCK/pid" 2>/dev/null)
    if supervisor_alive "$old"; then exit 0; fi
    # A freshly created lock may not have its pid yet.
    sleep 2
    old=$(cat "$LOCK/pid" 2>/dev/null)
    if supervisor_alive "$old"; then exit 0; fi
    rm -rf "$LOCK"
    mkdir "$LOCK" 2>/dev/null || exit 0
fi
echo $$ > "$LOCK/pid"
child=''
cleanup() {
    if child_alive "$child"; then
        kill "$child" 2>/dev/null
        sleep 1
        child_alive "$child" && kill -9 "$child" 2>/dev/null
    fi
    rm -f "$D/child.pid"
    rm -rf "$LOCK"
}
trap 'exit 0' TERM INT
trap cleanup EXIT
delay=3
while [ -f "$D/enabled" ]; do
    previous=$(cat "$D/child.pid" 2>/dev/null)
    if child_alive "$previous"; then
        # Recover a killed supervisor without duplicating its surviving child.
        child=$previous
        printf '%s [守护] 接管现有 frpc\n' "$(date '+%F %T')" >> "$D/frpc.log"
    else
        printf '%s [守护] 启动 frpc\n' "$(date '+%F %T')" >> "$D/frpc.log"
        "$D/frpc" -c "$D/frpc.toml" >> "$D/frpc.log" 2>&1 &
        child=$!
        echo "$child" > "$D/child.pid"
        # Give the forked shell time to exec frpc before checking /proc/exe.
        sleep 1
    fi
    ticks=0
    while child_alive "$child"; do
        [ -f "$D/enabled" ] || exit 0
        sleep 2
        ticks=$((ticks + 1))
        # Bound stdout storage even while a child keeps the descriptor open.
        size=$(stat -c %s "$D/frpc.log" 2>/dev/null)
        if [ "${size:-0}" -gt 2097152 ]; then
            tail -c 65536 "$D/frpc.log" > "$D/frpc.previous.log"
            : > "$D/frpc.log"
        fi
    done
    wait "$child"
    code=$?
    child=''
    rm -f "$D/child.pid"
    [ -f "$D/enabled" ] || break
    [ "$ticks" -ge 30 ] && delay=3
    printf '%s [守护] frpc 退出 (%s)，%ss 后重启\n' "$(date '+%F %T')" "$code" "$delay" >> "$D/frpc.log"
    n=0
    while [ "$n" -lt "$delay" ] && [ -f "$D/enabled" ]; do sleep 1; n=$((n + 1)); done
    delay=$((delay * 2))
    [ "$delay" -gt 60 ] && delay=60
done
