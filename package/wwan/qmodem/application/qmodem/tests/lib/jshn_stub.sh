# Minimal jshn.sh replacement for qmodem fixture tests, backed by jq.
# Implements the json_* subset used by qmodem vendor/generic scripts.
# State: _JSHN_DOC (canonical json), _JSHN_CUR (jq path array of current
# container), _JSHN_STACK (space separated parent paths).

_JSHN_DOC='{}'
_JSHN_CUR='[]'
_JSHN_STACK=''

json_init()
{
    _JSHN_DOC='{}'
    _JSHN_CUR='[]'
    _JSHN_STACK=''
}

_jshn_pop()
{
    [ -z "$_JSHN_STACK" ] && return
    _JSHN_CUR=${_JSHN_STACK##* }
    if [ "$_JSHN_CUR" = "$_JSHN_STACK" ]; then
        _JSHN_STACK=''
    else
        _JSHN_STACK=${_JSHN_STACK% *}
    fi
}

# $1: key (empty appends to array), $2: jq value expression using $v
_jshn_add()
{
    _JSHN_DOC=$(printf '%s' "$_JSHN_DOC" | jq --argjson p "$_JSHN_CUR" --arg k "$1" --arg v "$2" '
        if ($k == "") and ((getpath($p) | type) == "array")
        then setpath($p + [(getpath($p) | length)]; '"$3"')
        else setpath($p + [$k]; '"$3"')
        end')
}

json_add_string() { _jshn_add "$1" "$2" '$v'; }
json_add_boolean() { _jshn_add "$1" "$2" '($v == "1" or $v == "true")'; }
json_add_int() { _jshn_add "$1" "$2" '(try ($v | tonumber) catch 0)'; }

# $1: key, $2: empty container literal ({} or [])
_jshn_open()
{
    local newpath
    _JSHN_DOC=$(printf '%s' "$_JSHN_DOC" | jq --argjson p "$_JSHN_CUR" --arg k "$1" --argjson value "$2" '
        if ($k == "") and ((getpath($p) | type) == "array")
        then setpath($p + [(getpath($p) | length)]; $value)
        else setpath($p + [$k]; $value)
        end')
    # fix the appended-array path to the real index
    newpath=$(printf '%s' "$_JSHN_DOC" | jq -c --argjson p "$_JSHN_CUR" --arg k "$1" '
        if ($k == "") and ((getpath($p) | type) == "array")
        then ($p + [(getpath($p) | length) - 1])
        else ($p + [$k])
        end')
    _JSHN_STACK="$_JSHN_STACK $_JSHN_CUR"
    _JSHN_CUR="$newpath"
}

json_add_object() { _jshn_open "$1" '{}'; }
json_add_array() { _jshn_open "$1" '[]'; }
json_close_object() { _jshn_pop; }
json_close_array() { _jshn_pop; }

json_select()
{
    [ "$1" = ".." ] && { _jshn_pop; return; }
    _JSHN_STACK="$_JSHN_STACK $_JSHN_CUR"
    _JSHN_CUR=$(printf '%s' "$_JSHN_CUR" | jq -c --arg k "$1" '
        if ($k | test("^[0-9]+$")) then . + [$k | tonumber] else . + [$k] end')
    _JSHN_DOC=$(printf '%s' "$_JSHN_DOC" | jq --argjson p "$_JSHN_CUR" '
        if getpath($p) == null then setpath($p; {}) else . end')
}

json_dump()
{
    printf '%s\n' "$_JSHN_DOC" | jq -c .
}
