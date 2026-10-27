#!/bin/sh

# Example Custom SMS Forward Script
# This is a template script that can be customized for specific needs
#
# Environment variables available:
# SMS_SENDER - sender phone number
# SMS_TIME - timestamp string  
# SMS_CONTENT - SMS content

# Log the SMS to a file
LOG_FILE="/tmp/sms_log.txt"
echo "$(date): SMS from $SMS_SENDER: $SMS_CONTENT" >> "$LOG_FILE"

# Send a notification to system log
logger -t sms_forwarder "New SMS from $SMS_SENDER: $SMS_CONTENT"

# Example: Forward to email using sendmail (if available)
if command -v sendmail >/dev/null 2>&1; then
    {
        echo "To: admin@example.com"
        echo "Subject: New SMS from $SMS_SENDER"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "Time: $SMS_TIME"
        echo "Sender: $SMS_SENDER" 
        echo "Content: $SMS_CONTENT"
    } | sendmail admin@example.com
fi

# Example: Write to a named pipe for other processes
PIPE_FILE="/tmp/sms_pipe"
if [ -p "$PIPE_FILE" ]; then
    echo "$SMS_SENDER|$SMS_TIME|$SMS_CONTENT" > "$PIPE_FILE"
fi

# Always return success unless there's a critical error
exit 0
