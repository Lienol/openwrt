# Stub for OpenWrt /lib/functions.sh used by fixture tests.
config_load() { :; }
config_get() { return 1; }
config_get_bool() { return 1; }
config_foreach() { :; }
config_list_foreach() { :; }
board_name() { echo 'fixture,generic'; }
