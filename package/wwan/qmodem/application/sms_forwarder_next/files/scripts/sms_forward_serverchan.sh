#!/bin/sh

# ServerChan SMS Forward Script (New API)
# Environment variables available:
# SMS_SENDER - sender phone number
# SMS_TIME - timestamp string
# SMS_CONTENT - SMS content

# Parse API config from environment or config file
API_CONFIG="$1"

if [ -z "$API_CONFIG" ]; then
    echo "Error: API config not provided"
    exit 1
fi

# Extract configuration using jq or manual parsing
TOKEN=$(echo "$API_CONFIG" | jq -r '.token' 2>/dev/null)
CHANNEL=$(echo "$API_CONFIG" | jq -r '.channel' 2>/dev/null)
NOIP=$(echo "$API_CONFIG" | jq -r '.noip' 2>/dev/null)
OPENID=$(echo "$API_CONFIG" | jq -r '.openid' 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo "Error: Missing required ServerChan token"
    exit 1
fi

# Build API URL with token
API_URL="https://sctapi.ftqq.com/${TOKEN}.send"

# Prepare message content
TITLE="QModem SMS: ($SMS_SENDER)"
DESP="**Time:** $SMS_TIME

**Sender:** $SMS_SENDER

**Content:** 
$SMS_CONTENT"

# URL encode function for GET method
url_encode() {
    echo "$1" | sed 's/ /%20/g;s/!/%21/g;s/"/%22/g;s/#/%23/g;s/\$/%24/g;s/&/%26/g;s/'\''/%27/g;s/(/%28/g;s/)/%29/g;s/\*/%2A/g;s/+/%2B/g;s/,/%2C/g;s/-/%2D/g;s/\./%2E/g;s/\//%2F/g;s/:/%3A/g;s/;/%3B/g;s/</%3C/g;s/=/%3D/g;s/>/%3E/g;s/?/%3F/g;s/@/%40/g;s/\[/%5B/g;s/\\/%5C/g;s/\]/%5D/g;s/\^/%5E/g;s/_/%5F/g;s/`/%60/g;s/{/%7B/g;s/|/%7C/g;s/}/%7D/g;s/~/%7E/g'
}

# Try curl first, then wget
if command -v curl >/dev/null 2>&1; then
    #使用jq生成JSON_DATA
    JSON_DATA=`
    jq -n --arg title "$TITLE" --arg desp "$DESP" '
        {
            title: $title,
            desp: $desp
        }'`
    [ -n "$CHANNEL" ] && JSON_DATA=$(echo "$JSON_DATA" | jq --arg channel "$CHANNEL" '. + {channel: $channel}')
    [ -n "$NOIP" ] && JSON_DATA=$(echo "$JSON_DATA" | jq --arg noip "$NOIP" '. + {noip: $noip}')
    [ -n "$OPENID" ] && JSON_DATA=$(echo "$JSON_DATA" | jq --arg openid "$OPENID" '. + {openid: $openid}')


    curl -X POST "$API_URL" \
        -H "Content-Type: application/json;charset=utf-8" \
        -d "$JSON_DATA" \
        --connect-timeout 10 \
        --max-time 30
elif command -v wget >/dev/null 2>&1; then
    # Use GET method with URL encoding for wget
    ENCODED_TITLE=$(url_encode "$TITLE")
    ENCODED_DESP=$(url_encode "$DESP")
    
    # Build query string
    QUERY="title=$ENCODED_TITLE&desp=$ENCODED_DESP"
    [ -n "$CHANNEL" ] && QUERY="${QUERY}&channel=$CHANNEL"
    [ -n "$NOIP" ] && QUERY="${QUERY}&noip=$NOIP"
    [ -n "$OPENID" ] && QUERY="${QUERY}&openid=$(url_encode "$OPENID")"
    
    wget -O- \
        --timeout=30 \
        "${API_URL}?${QUERY}"
else
    echo "Error: Neither curl nor wget available"
    exit 1
fi

exit $?
