# Connecting TokenStat to Telegram

TokenStat can send you a Telegram message the moment Claude Code turns ready (green) — useful if you're away from your Mac and don't want to rely on the macOS notification alone.

## 1. Create a bot with BotFather

1. Open Telegram and start a chat with [@BotFather](https://t.me/BotFather).
2. Send `/newbot` and follow the prompts (choose a name and a username ending in `bot`).
3. BotFather replies with your **Bot Token** — a string like:
   ```
   123456789:AAHk3jX9pQ2z...
   ```
   Keep this private; anyone with it can send messages as your bot.

## 2. Get your Chat ID

Your bot can't message you until you've messaged it first, and you need your **Chat ID** to tell TokenStat where to send messages.

1. In Telegram, search for the bot you just created (by its username) and send it any message, e.g. `hi`.
2. In a browser, open:
   ```
   https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates
   ```
   replacing `<YOUR_BOT_TOKEN>` with the token from step 1.
3. Look for `"chat":{"id":123456789,...}` in the JSON response — that number is your **Chat ID**.

   (Alternative: message [@userinfobot](https://t.me/userinfobot) — it replies with your Chat ID directly.)

## 3. Configure TokenStat

1. Click the TokenStat icon in the menu bar → **Settings…**
2. Under **Telegram**, paste your **Bot Token** and **Chat ID**.
3. Click **Test** — you should get a message from your bot in Telegram within a couple seconds.
4. Check **Notify via Telegram when ready** and click **Save**.

From then on, every time Claude Code finishes a turn and is ready for your next prompt, TokenStat sends:

```
✅ Claude Code is ready for your next prompt
```

## Troubleshooting

| Test button shows | Likely cause |
|---|---|
| `Invalid bot token` | Token was mistyped or missing the `:` separator |
| `HTTP 401: ...` | Wrong bot token |
| `HTTP 400: Bad Request: chat not found` | Chat ID is wrong, or you haven't messaged the bot yet |
| No response / network error | No internet connection, or Telegram is unreachable |

## Notes

- The Bot Token and Chat ID are stored locally in `UserDefaults` (`com.tokenstat.app`) — nothing is sent anywhere except directly to `api.telegram.org`.
- This feature is fully optional and off by default.
