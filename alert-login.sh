#!/usr/bin/env bash

# --- Load environment configuration ---
# Expected .alert-login.env file placed beside this script (same directory when installed)
# Variables: ALERT_TYPES (comma list: mail,slack,telegram), RECIPIENT, FROM_ADDR,
# SLACK_WEBHOOK_URL, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, ENABLE_IP_GEO
ENV_FILE="$(dirname "$0")/.alert-login.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a
  . "$ENV_FILE"
  set +a
else
  logger -t alert-login "WARNING: .alert-login.env file not found at $ENV_FILE; using defaults"
fi

# Defaults if not set
ALERT_TYPES=${ALERT_TYPES:-mail}
# Toggle IP geolocation (curl to ipinfo.io). Set to "false" to disable.
ENABLE_IP_GEO=${ENABLE_IP_GEO:-true}

# Basic validation: if mail is requested ensure RECIPIENT + FROM_ADDR exist
if echo "$ALERT_TYPES" | grep -qi 'mail'; then
  : "${RECIPIENT:?RECIPIENT missing in .alert-login.env}" || exit 1
  : "${FROM_ADDR:?FROM_ADDR missing in .alert-login.env}" || exit 1
fi

# Ensure minimal safe environment for PAM-run scripts
export PATH="/usr/sbin:/sbin:/usr/bin:/bin:/usr/local/bin"
# Prefer a UTF-8 locale when available to avoid mail charset encoding errors
if locale -a 2>/dev/null | grep -iq '^c\.utf-8$'; then
  export LANG=C.utf8 LC_ALL=C.utf8
elif locale -a 2>/dev/null | grep -Ei '^en(_|)us\.(utf8|utf-8)$' >/dev/null 2>&1; then
  export LANG=en_US.utf8 LC_ALL=en_US.utf8
elif locale -a 2>/dev/null | grep -iq '^en_US\.utf8$'; then
  export LANG=en_US.utf8 LC_ALL=en_US.utf8
else
  # Fallback to C.utf8 which exists on many systems
  export LANG=C.utf8 LC_ALL=C.utf8
fi

# --- Log redirection for debugging ---
exec &> /var/log/ssh-alert.log

# --- PAM Variables ---
USER_NAME="${PAM_USER:-unknown}"
HOST="${PAM_RHOST:-localhost}"
SERVER="$(hostname)"
DATE="$(/usr/bin/date '+%A %d %B %Y %H:%M:%S')"
ISROOT="No"
[ "$USER_NAME" == "root" ] && ISROOT="Yes"
TTY="${PAM_TTY:-unknown}"
SESSION_TYPE="Interactive"
[[ "$TTY" == "unknown" ]] && SESSION_TYPE="Non-interactive"

# --- Full paths ---
CURL="/usr/bin/curl"
SENDMAIL="/usr/sbin/sendmail"
MAILX="/usr/bin/mailx"

# --- IP Geolocation ---
if [ "$HOST" != "localhost" ]; then
  if [ "$ENABLE_IP_GEO" = "true" ] || [ "$ENABLE_IP_GEO" = "1" ]; then
    LOCATION=$($CURL -s "https://ipinfo.io/$HOST/json" \
      | grep -E '"city"|region|country' \
      | sed -E 's/.*"([^"]+)".*/\1/' \
      | paste -sd ', ')
    [ -z "$LOCATION" ] && LOCATION="Unknown (geolocation lookup failed)"
  else
    LOCATION="Geolocation disabled"
  fi
else
  LOCATION="Localhost / Internal connection"
fi

# --- Email subject ---
SUBJECT="[Alert] New SSH connection: $USER_NAME on $SERVER"

# --- HTML body ---
BODY=$(cat <<EOF
<html>
  <body style="font-family:Arial,sans-serif;color:#333;">
    <h2 style="color:#2E86C1;">New SSH connection detected</h2>
    <table style="border-collapse:collapse;">
      <tr><td style="padding:4px;font-weight:bold;">User:</td><td style="padding:4px;">${USER_NAME}</td></tr>
      <tr><td style="padding:4px;font-weight:bold;">Root:</td><td style="padding:4px;">${ISROOT}</td></tr>
      <tr><td style="padding:4px;font-weight:bold;">IP Address:</td><td style="padding:4px;">${HOST}</td></tr>
      <tr><td style="padding:4px;font-weight:bold;">Location:</td><td style="padding:4px;">${LOCATION}</td></tr>
      <tr><td style="padding:4px;font-weight:bold;">Server:</td><td style="padding:4px;">${SERVER}</td></tr>
      <tr><td style="padding:4px;font-weight:bold;">Date:</td><td style="padding:4px;">${DATE}</td></tr>
      <tr><td style="padding:4px;font-weight:bold;">Session:</td><td style="padding:4px;">${SESSION_TYPE}</td></tr>
      <tr><td style="padding:4px;font-weight:bold;">TTY:</td><td style="padding:4px;">${TTY}</td></tr>
    </table>
    <hr>
    <p style="font-size:small;color:#888;">This email was generated automatically by the SSH alert script.</p>
  </body>
</html>
EOF
)

# --- Prepare text version ---
TEXT_BODY=$(cat <<EOF
🔔 SSH Connection Alert

A new SSH connection has been detected.

Details:
• User: ${USER_NAME}
• Root: ${ISROOT}
• IP Address: ${HOST}
• Location: ${LOCATION}
• Server: ${SERVER}
• Date: ${DATE}
• Session Type: ${SESSION_TYPE}
• TTY: ${TTY}

This message was generated automatically by the SSH alert script.
EOF
)



# --- Functions for alerting channels ---
send_mail_alert() {
  if [ -x "${SENDMAIL}" ]; then
      logger -t alert-login "Using sendmail for HTML message"
      BOUNDARY="==_Boundary_${RANDOM}_${RANDOM}"
      {
          printf '%s\n' "From: ${FROM_ADDR}"
          printf '%s\n' "To: ${RECIPIENT}"
          printf '%s\n' "Subject: ${SUBJECT}"
          printf '%s\n' "MIME-Version: 1.0"
          printf '%s\n' "Content-Type: multipart/alternative; boundary=\"${BOUNDARY}\""
          printf '\n'
          printf '%s\n' "--${BOUNDARY}"
          printf '%s\n' 'Content-Type: text/plain; charset=UTF-8'
          printf '%s\n' 'Content-Transfer-Encoding: quoted-printable'
          printf '\n'
          printf '%s\n' "${TEXT_BODY}"
          printf '\n'
          printf '%s\n' "--${BOUNDARY}"
          printf '%s\n' 'Content-Type: text/html; charset=UTF-8'
          printf '%s\n' 'Content-Transfer-Encoding: quoted-printable'
          printf '\n'
          printf '%s\n' "${BODY}"
          printf '%s\n' "--${BOUNDARY}--"
      } | "${SENDMAIL}" -t -i && return 0
      logger -t alert-login "sendmail failed, falling back to mailx"
  fi
  if [ -x "${MAILX}" ]; then
      logger -t alert-login "Using mailx (text-only mode)"
      printf '%s\n' "${TEXT_BODY}" | "${MAILX}" -s "${SUBJECT}" "${RECIPIENT}" && return 0
      logger -t alert-login "mailx failed"
  fi
  logger -t alert-login "ERROR: Both sendmail and mailx failed"
  return 1
}

send_slack_alert() {
  [ -z "${SLACK_WEBHOOK_URL}" ] && logger -t alert-login "Slack webhook missing; skip" && return 1
  local text
  text="SSH Alert: user=${USER_NAME} root=${ISROOT} ip=${HOST} location=${LOCATION} server=${SERVER} date=${DATE} session=${SESSION_TYPE} tty=${TTY}"
  ${CURL} -s -X POST -H 'Content-type: application/json' --data "$(printf '{"text":"%s"}' "${text}")" "${SLACK_WEBHOOK_URL}" >/dev/null 2>&1 && return 0
  logger -t alert-login "Slack notification failed"
  return 1
}

send_telegram_alert() {
  [ -z "${TELEGRAM_BOT_TOKEN}" ] && logger -t alert-login "Telegram bot token missing; skip" && return 1
  [ -z "${TELEGRAM_CHAT_ID}" ] && logger -t alert-login "Telegram chat id missing; skip" && return 1
  local text
  text="🔔 *SSH Login Alert*%0A👤 *User:* ${USER_NAME}%0A🔑 *Root:* ${ISROOT}%0A🌐 *IP:* ${HOST}%0A📍 *Location:* ${LOCATION}%0A🖥️ *Server:* ${SERVER}%0A📅 *Date:* ${DATE}%0A💻 *Session:* ${SESSION_TYPE}%0A🖲️ *TTY:* ${TTY}"
  ${CURL} -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" -d "text=${text}" -d "parse_mode=Markdown" >/dev/null 2>&1 && return 0
  logger -t alert-login "Telegram notification failed"
  return 1
}

# --- Dispatch based on ALERT_TYPES ---
IFS=',' read -r -a _ALERT_ARRAY <<< "$ALERT_TYPES"
for ch in "${_ALERT_ARRAY[@]}"; do
  case "${ch}" in
    mail|MAIL)
      send_mail_alert
      ;;
    slack|SLACK)
      send_slack_alert
      ;;
    telegram|TELEGRAM)
      send_telegram_alert
      ;;
    *)
      logger -t alert-login "Unknown alert channel: ${ch}"
      ;;
  esac
done

exit 0