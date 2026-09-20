#!/usr/bin/env python3
"""Interactive setup: credentials never appear in argv or logs."""
import getpass, json, urllib.request, urllib.error
from urllib.parse import urlparse

def main():
    token = getpass.getpass('Bot token (hidden): ').strip()
    secret = getpass.getpass('Same TELEGRAM_WEBHOOK_SECRET as Firebase (hidden): ').strip()
    url = input('HTTPS telegramWebhook function URL: ').strip()
    if len(secret) < 32 or not all(c.isalnum() or c in '_-' for c in secret):
        raise SystemExit('Use a secret of at least 32 ASCII letters, digits, underscore or hyphen.')
    if urlparse(url).scheme != 'https':
        raise SystemExit('HTTPS is required')
    data = json.dumps({'url':url, 'secret_token':secret, 'allowed_updates':['channel_post','edited_channel_post'], 'drop_pending_updates':False}).encode()
    req = urllib.request.Request('https://api.telegram.org/bot'+token+'/setWebhook',data=data,headers={'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            result = json.load(response)
        print('Webhook registered.' if result.get('ok') else 'Telegram rejected setup; verify token and URL.')
    except (urllib.error.URLError, ValueError):
        raise SystemExit('Webhook setup failed. Check network, token and HTTPS endpoint. Credentials were not logged.')
if __name__ == '__main__':
    main()
