# Hex helper shared by fixture tests. qmodem directly depends on full xxd.
fixture_hex_decode()
{
    printf '%s' "$1" | xxd -r -p
}
