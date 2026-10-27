# Replay recorded fixtures instead of touching hardware.
# Requires FIXTURE_LOOKUP: a dir with <md5(command)>.response / .rc files.

at() { _fixture_send at "$@"; }
fastat() { _fixture_send fastat "$@"; }

_fixture_send()
{
    _fs_cmd=$3
    _fs_h=$(printf '%s' "$_fs_cmd" | md5sum | cut -c1-8)
    if [ -f "$FIXTURE_LOOKUP/$_fs_h.response" ]; then
        cat "$FIXTURE_LOOKUP/$_fs_h.response"
        _fs_rc=0
        [ -f "$FIXTURE_LOOKUP/$_fs_h.rc" ] && _fs_rc=$(cat "$FIXTURE_LOOKUP/$_fs_h.rc")
        return "$_fs_rc"
    fi
    echo "$_fs_cmd" >> "$FIXTURE_LOOKUP/misses.log"
    return 0
}
