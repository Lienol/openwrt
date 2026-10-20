#!/bin/sh
# QModem SMS → Feishu message card webhook
# Version: 2025-11-02
# author: XRSec <github.com/XRSec>

API_CONFIG="$1"
# {"webhook_key":"xxxxxx"}


# 飞书 webhook
WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/"

# 设备 / 应用信息
DEVICE_NAME="自定义"
APP_NAME="QModem"
CALL_TYPE="SMS"
TITLE="短信通知"
WEBHOOK_KEY=$(echo "$API_CONFIG" | jq -r .webhook_key)
WEBHOOK="${WEBHOOK}${WEBHOOK_KEY}"

# 从环境变量读取短信信息
FROM="${SMS_SENDER:-unknown}"
RECEIVE_TIME="${SMS_TIME:-$(date '+%Y-%m-%d %H:%M:%S')}"
MSG="${SMS_CONTENT:-<empty>}"

# 限制短信长度（防止过长）
MAX_LEN=800
if [ "${#MSG}" -gt "$MAX_LEN" ]; then
  MSG="$(printf '%s' "$MSG" | cut -c1-${MAX_LEN})..."
fi

# JSON 转义
escape_json() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'
}

FROM_ESC="$(escape_json "$FROM")"
MSG_ESC="$(escape_json "$MSG")"
RECEIVE_TIME_ESC="$(escape_json "$RECEIVE_TIME")"

# 构造飞书卡片 JSON
JSON_PAYLOAD=$(cat <<EOF
{
  "msg_type": "interactive",
  "card": {
    "header": {
      "template": "blue",
      "title": {
        "content": "💬${DEVICE_NAME}",
        "tag": "plain_text"
      }
    },
    "elements": [
      {
        "tag": "div",
        "fields": [
          {
            "is_short": true,
            "text": {"tag": "lark_md","content": "**🕙接收时间：** ${RECEIVE_TIME_ESC}"}
          },
          {
            "is_short": true,
            "text": {"tag": "lark_md","content": "**📞来源号码：** ${FROM_ESC}"}
          }
        ]
      },
      {
        "tag": "div",
        "fields": [
          {
            "is_short": true,
            "text": {"tag": "lark_md","content": "**📱设备名称：** ${DEVICE_NAME}"}
          },
          {
            "is_short": true,
            "text": {"tag": "lark_md","content": "**📲App应用名：** ${APP_NAME}"}
          }
        ]
      },
      {
        "tag": "div",
        "fields": [
          {
            "is_short": true,
            "text": {"tag": "lark_md","content": "**📞通话类型：** ${CALL_TYPE}"}
          },
          {
            "is_short": true,
            "text": {"tag": "lark_md","content": "**📢通知标题：** ${TITLE}"}
          }
        ]
      },
      {
        "tag": "div",
        "fields": [
          {
            "is_short": true,
            "text": {"tag": "lark_md","content": "**📝通知内容：** ${MSG_ESC}"}
          }
        ]
      }
    ]
  }
}
EOF
)

# 日志输出到系统 logread
logger -t sms_forward "📩 短信来自 ${FROM}，长度 ${#MSG} 字符，准备推送到飞书..."

# 简单重试机制（最多 3 次）
RETRY=0
MAX_RETRY=3
while [ "$RETRY" -lt "$MAX_RETRY" ]; do
  RETRY=$((RETRY + 1))
  curl -sS -m 10 -X POST -H "Content-Type: application/json" \
    -d "${JSON_PAYLOAD}" "${WEBHOOK}" >/dev/null 2>&1
  STATUS=$?

  if [ "$STATUS" -eq 0 ]; then
    logger -t sms_forward "✅ 成功转发短信至飞书 (${FROM})"
    exit 0
  else
    logger -t sms_forward "⚠️ 第 ${RETRY} 次发送失败 (code=${STATUS})，重试中..."
    sleep 3
  fi
done

logger -t sms_forward "❌ 最终发送失败 (${FROM})，放弃重试。"
exit 1
