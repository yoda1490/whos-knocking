# 🚪 Who's Knocking?

*Because you should always know who's at your SSH door!*

A SSH login alert system that sends beautiful HTML email notifications whenever someone logs into your Linux server. Get instant alerts with IP geolocation, user details, and session information.

## 🎯 Features

- **Real-time SSH Login Alerts** - Instant notifications via email
- **Beautiful HTML Emails** - Formatted with tables and styling
- **IP Geolocation** - Automatically determines the location of the connecting IP
- **Root Login Detection** - Clearly indicates if root user logged in
- **Session Type Detection** - Distinguishes between interactive and non-interactive sessions
- **Dual Delivery Methods** - Uses `sendmail` with HTML fallback to `mailx` text-only
- **Comprehensive Logging** - All activity logged to `/var/log/ssh-alert.log`
- **PAM Integration** - Seamlessly hooks into the SSH authentication process

## 📋 Prerequisites

- Linux server with SSH enabled
- `curl` installed (for IP geolocation)
- Either `sendmail` or `mailx` configured for email delivery
- PAM (Pluggable Authentication Modules) support
- Root access for installation

## 🔧 Installation

### 1. Copy the Script

```bash
# Copy the script to /usr/local/bin
sudo cp alert-login.sh /usr/local/bin/

# Make it executable
sudo chmod +x /usr/local/bin/alert-login.sh
```

### 2. Configure Environment (.alert-login.env)

All sensitive and channel-specific settings are now stored in a `.alert-login.env` file next to the script. An example file is provided as `.alert-login.env.example`.

Copy it and edit values:

```bash
cp /usr/local/bin/.alert-login.env.example /usr/local/bin/.alert-login.env
vi /usr/local/bin/.alert-login.env
```

Variables:

| Name | Required For | Description |
|------|--------------|-------------|
| `ALERT_TYPES` | all | Comma list of channels: `mail,slack,telegram` (default: `mail`) |
| `RECIPIENT` | mail | Destination email address |
| `FROM_ADDR` | mail | From/sender email address |
| `SLACK_WEBHOOK_URL` | slack | Incoming webhook URL |
| `TELEGRAM_BOT_TOKEN` | telegram | Bot token from @BotFather |
| `TELEGRAM_CHAT_ID` | telegram | Chat or group ID receiving messages |
| `ENABLE_IP_GEO` | all | Enable IP geolocation via ipinfo.io (`true` by default). Set to `false` to disable and avoid external requests. |

Leave unused channel variables blank or omit the channel from `ALERT_TYPES`.

### 3. Enable PAM Integration

Add the following line to your `/etc/pam.d/sshd` file:

```
session   optional  pam_exec.so /usr/local/bin/alert-login.sh
```

**Important:** The `session optional pam_exec.so` line should be added at the end of the session section.

### 4. Set Up Logging

```bash
# Create the log file
sudo touch /var/log/ssh-alert.log

# Set appropriate permissions
sudo chmod 644 /var/log/ssh-alert.log
```

### 5. Test the Setup

Log in via SSH from another terminal or machine. You should receive alerts for each channel defined in `ALERT_TYPES`.

## 📢 Alert Channels

The script supports multiple alert channels via `ALERT_TYPES`.

### Mail
Order:
1. `sendmail` (multipart HTML + text)
2. Fallback: `mailx` (plain text)

### Configuring Sendmail

Most Linux distributions come with a basic MTA. For Debian/Ubuntu:

```bash
sudo apt-get install sendmail
sudo sendmailconfig
```

For Arch Linux:

```bash
sudo pacman -S sendmail
sudo systemctl enable sendmail
sudo systemctl start sendmail
```

### Configuring Mailx (Alternative)
### Slack

1. Create an Incoming Webhook in your Slack workspace.
2. Set `SLACK_WEBHOOK_URL` in `.alert-login.env`.
3. Add `slack` to `ALERT_TYPES` (e.g. `ALERT_TYPES=mail,slack`).

The payload contains a concise line with user, IP, and context.

### Telegram

1. Create a bot with @BotFather, obtain the token.
2. Get your chat ID (send a message to the bot, then query `https://api.telegram.org/botTOKEN/getUpdates`).
3. Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in `.alert-login.env`.
4. Add `telegram` to `ALERT_TYPES`.

Messages are sent using the standard `sendMessage` endpoint.

```bash
# Debian/Ubuntu
sudo apt-get install mailutils

# Arch Linux
sudo pacman -S mailutils
```

## 🔍 Data in Each Alert

Each alert email includes:

- **Username** - The account that logged in
- **Root Status** - Whether it's a root login (Yes/No)
- **IP Address** - Source IP of the connection
- **Location** - Geolocation info (City, Region, Country)
- **Server** - Hostname of your server
- **Date & Time** - When the login occurred
- **Session Type** - Interactive or Non-interactive
- **TTY** - Terminal information

## 🐛 Troubleshooting

### Not receiving emails?

1. Check the log file: `sudo tail -f /var/log/ssh-alert.log`
2. Verify email configuration is working: `echo "test" | mail -s "test" your-email@example.com`
3. Check system logs: `sudo journalctl -xe | grep pam_exec`
4. Verify the script has execute permissions: `ls -l /usr/local/bin/alert-login.sh`

### Script not being triggered?

1. Verify PAM configuration: `cat /etc/pam.d/sshd`
2. Check SELinux/AppArmor isn't blocking execution
3. Ensure the script path in PAM config is correct

### Geolocation not working?

1. Test curl manually: `curl -s "https://ipinfo.io/8.8.8.8/json"`
2. Check firewall rules allow outbound HTTPS
3. Verify `curl` is installed: `which curl`

## 🎨 Customization

### Change Email Format

Edit the `BODY` variable in the script to customize the HTML template.

### Add More Information

You can add additional PAM variables or system information to the email. Common PAM variables:

- `$PAM_USER` - Username
- `$PAM_RHOST` - Remote host
- `$PAM_SERVICE` - Service name (sshd)
- `$PAM_TTY` - Terminal

### Filter Specific Users

Add a condition to skip alerts for certain users:

```bash
# Skip alerts for specific users
if [[ "$USER_NAME" == "monitoring" || "$USER_NAME" == "backup" ]]; then
    exit 0
fi
```

## 🔒 Security Considerations
* Avoid committing `.alert-login.env` to version control.
* Restrict permissions: `chmod 600 .alert-login.env` if it contains sensitive tokens.
* Rotate Slack webhook / Telegram bot token if exposed.

- The script runs with PAM privileges, so keep it secure
- Restrict write access: `sudo chmod 755 /usr/local/bin/alert-login.sh`
- Review the script before installation
- Consider rate limiting if you have high-frequency logins
- Protect your log file: only root should write to it

## 📝 License

This project is open source. Feel free to modify and distribute as needed.

## 🤝 Contributing

Suggestions and improvements welcome! This is a community project to help sysadmins sleep better at night.



---

*Keep calm and monitor your servers!* 🔐

