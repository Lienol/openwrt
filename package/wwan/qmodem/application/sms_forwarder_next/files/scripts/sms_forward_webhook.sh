#!/bin/sh

# Webhook SMS Forward Script
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
WEBHOOK_URL=$(echo "$API_CONFIG" | jq -r '.webhook_url' 2>/dev/null)
HEADERS=$(echo "$API_CONFIG" | jq -r '.headers' 2>/dev/null)
FORMAT=$(echo "$API_CONFIG" | jq -r '.format' 2>/dev/null)
REQUEST_METHOD=$(echo "$API_CONFIG" | jq -r '.request_method' 2>/dev/null)
echo "$API_CONFIG" | jq
# Fallback to manual parsing if jq fails
if [ -z "$WEBHOOK_URL" ] || [ "$WEBHOOK_URL" = "null" ]; then
    WEBHOOK_URL=$(echo "$API_CONFIG" | grep -o '"webhook_url":"[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$HEADERS" ] || [ "$HEADERS" = "null" ]; then
    HEADERS=$(echo "$API_CONFIG" | grep -o '"headers":"[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$WEBHOOK_URL" ]; then
    echo "Error: Missing required webhook URL"
    exit 1
fi

# Prepare payload based on format
if [ -z "$FORMAT" ] || [ "$FORMAT" = "null" ];then
    payload="$SMS_SENDER/$SMS_CONTENT($SMS_TIME)"
else
    # Safe placeholder replacement using awk (handles all special characters)
    payload=$(printf '%s' "$FORMAT" | awk -v sender="$SMS_SENDER" -v time="$SMS_TIME" -v content="$SMS_CONTENT" '
    {
        gsub(/\{SENDER\}/, sender)
        gsub(/\{TIME\}/, time)
        gsub(/\{CONTENT\}/, content)
        print
    }')
    
    WEBHOOK_URL=$(printf '%s' "$WEBHOOK_URL" | awk -v sender="$SMS_SENDER" -v time="$SMS_TIME" -v content="$SMS_CONTENT" '
    {
        gsub(/\{SENDER\}/, sender)
        gsub(/\{TIME\}/, time)
        gsub(/\{CONTENT\}/, content)
        print
    }')
fi

# Prepare curl command
if [ -z "$REQUEST_METHOD" ] || [ "$REQUEST_METHOD" = "null" ]; then
    REQUEST_METHOD="GET"
fi


if [ "$REQUEST_METHOD" = "POST" ]; then
    # Build curl arguments array-style for proper quoting
    if [ -n "$HEADERS" ]; then
        curl -X POST "$WEBHOOK_URL" -d "$payload" -H "Content-Type: application/json" -H "$HEADERS"
    else
        curl -X POST "$WEBHOOK_URL" -d "$payload" -H "Content-Type: application/json"
    fi
else
    # URL-encode payload for GET request
    # Use jq for reliable URL encoding
    encoded_payload=$(printf '%s' "$payload" | jq -sRr @uri)
    full_url="${WEBHOOK_URL}/${encoded_payload}"
    
    if [ -n "$HEADERS" ]; then
        curl "$full_url" -H "$HEADERS"
    else
        curl "$full_url"
    fi
fi

exit $?
