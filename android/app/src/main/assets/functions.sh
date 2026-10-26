#!/system/bin/sh
valid_pid() {
    case "$1" in ''|*[!0-9]*) return 1;; esac
    [ "$1" -gt 1 ] 2>/dev/null
}
child_alive() {
    valid_pid "$1" || return 1
    [ "$(readlink /proc/"$1"/exe 2>/dev/null)" = /data/adb/frpc-android/frpc ] || return 1
    kill -0 "$1" 2>/dev/null
}
supervisor_alive() {
    valid_pid "$1" || return 1
    tr '\000' '\n' < /proc/"$1"/cmdline 2>/dev/null | grep -qx /data/adb/frpc-android/supervisor.sh || return 1
    kill -0 "$1" 2>/dev/null
}
