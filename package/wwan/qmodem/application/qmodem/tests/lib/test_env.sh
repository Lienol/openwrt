# Common environment for qmodem fixture tests (sourced).
# Points the QMODEM_* seams at the repo tree and stubs device tools.

TESTS_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PKG_DIR=$(CDPATH= cd "$TESTS_DIR/.." && pwd)
REPO_ROOT=${QMODEM_TEST_REPO_ROOT:-$(CDPATH= cd "$PKG_DIR/../.." && pwd)}

export QMODEM_HOME="$PKG_DIR/files/usr/share/qmodem"
export QMODEM_JSHN="$TESTS_DIR/lib/jshn_stub.sh"
export QMODEM_LIB_FUNCTIONS="$TESTS_DIR/lib/functions_stub.sh"
# never record fixtures during replay
export QMODEM_COLLECT_TESTCASE=0
. "$TESTS_DIR/lib/hex.sh"

# modem_ctrl normally provides these globals before dispatching a vendor method.
at_port=${at_port:-/dev/ttyUSB2}
platform=${platform:-qualcomm}
define_connect=${define_connect:-0}
config_section=${config_section:-fixture}
export at_port platform define_connect config_section

uci()
{
    case "$*" in
        *qmodem.fixture.modes*) printf '%s\n' "${QMODEM_TESTCASE_MODES:-}" ;;
        *qmodem.fixture.wcdma_band*) printf '%s\n' "${QMODEM_TESTCASE_WCDMA_BAND:-}" ;;
        *qmodem.fixture.lte_band*) printf '%s\n' "${QMODEM_TESTCASE_LTE_BAND:-}" ;;
        *qmodem.fixture.nsa_band*) printf '%s\n' "${QMODEM_TESTCASE_NSA_BAND:-}" ;;
        *qmodem.fixture.sa_band*) printf '%s\n' "${QMODEM_TESTCASE_SA_BAND:-}" ;;
        *qmodem.fixture.manufacturer*) printf '%s\n' "${vendor:-core}" ;;
        *qmodem.fixture.platform*) printf '%s\n' "${platform:-unknown}" ;;
        *qmodem.fixture.name*) printf '%s\n' "${QMODEM_TESTCASE_MODEL:-unknown}" ;;
        *) return 1 ;;
    esac
}
logger() { :; }
