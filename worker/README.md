# راه‌اندازی Cloudflare رایگان برای نبض خبر

این سرور جایگزین Firebase برای **خواندن خبرهای کانال** است. اعلان فوری در پس‌زمینه با این سرور به تنهایی فعال نمی‌شود؛ برای آن باید FCM جداگانه راه‌اندازی شود.

## ۱. ساخت دیتابیس D1

در https://dash.cloudflare.com/ به Workers & Pages و D1 SQL Database بروید، Create database را بزنید و نام telegram-news-db را وارد کنید. در Console دیتابیس، محتوای فایل worker/schema.sql مخزن را اجرا کنید. شناسه Database ID ساخته‌شده را کپی کنید و در GitHub، فایل worker/wrangler.toml را ویرایش کنید: REPLACE_WITH_D1_DATABASE_ID را با شناسه واقعی جایگزین کرده و Commit کنید.

## ۲. استقرار از GitHub (قابل انجام از مرورگر گوشی)

Cloudflare → Workers & Pages → Create application → Import a repository. مخزن ahbe0911-cmd/TelegramNews را انتخاب کنید. نام Worker باید telegram-news-free و Root directory برابر worker باشد. دستور استقرار npx wrangler deploy است. Cloudflare پس از استقرار نشانی شبیه https://telegram-news-free.YOUR_ACCOUNT.workers.dev می‌دهد. مسیر /health باید پاسخ JSON با ok: true بدهد.

## ۳. ثبت اطلاعات محرمانه ربات

Cloudflare → Worker → Settings → Variables and Secrets → Add: دو متغیر از نوع Secret بسازید:

- TELEGRAM_BOT_TOKEN : توکن شخصی ربات @Ahbe1400_bot از BotFather
- TELEGRAM_WEBHOOK_SECRET : یک رشته تصادفی حداقل ۳۲ کاراکتری از حروف و اعداد انگلیسی و _ یا -

هر دو را Deploy کنید. هرگز توکن یا Secret را در GitHub، APK یا پیام گفتگو قرار ندهید. ربات باید مدیر کانال عمومی @ahbe1400 باشد.

## ۴. ثبت وب‌هوک تلگرام

وب‌هوک در این نسخه خودکار ثبت نمی‌شود. از API رسمی Telegram Bot API و روش POST setWebhook استفاده کنید:
Endpoint: https://api.telegram.org/bot<BOT_TOKEN>/setWebhook
پارامتر url: https://YOUR_WORKER_URL/telegram/webhook
پارامتر secret_token: همان TELEGRAM_WEBHOOK_SECRET
پارامتر allowed_updates: ["channel_post","edited_channel_post"]

نمونه دستور در ترمینال شخصی؛ توکن و رمز را تعاملی وارد کنید (نه در چت یا مخزن):

```bash
read -rs -p 'Bot token: ' BOT_TOKEN; echo
read -rs -p 'Webhook secret: ' HOOK_SECRET; echo
read -r -p 'Worker URL: ' WORKER_URL
curl -fsS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/setWebhook" \
  --data-urlencode "url=${WORKER_URL%/}/telegram/webhook" \
  --data-urlencode "secret_token=${HOOK_SECRET}" \
  --data-urlencode 'allowed_updates=["channel_post","edited_channel_post"]'
unset BOT_TOKEN HOOK_SECRET
```

## ۵. اتصال برنامه اندروید

پس از ثبت وب‌هوک یک پست **تازه** در کانال بفرستید. https://YOUR_WORKER_URL/posts باید آن را برگرداند. در GitHub → Settings → Secrets and variables → Actions → Variables یک Variable به نام API_BASE_URL بسازید و مقدار آن را برابر نشانی پایه Worker (بدون /posts) قرار دهید. سپس در Actions گردش‌کار Build A54 APK را اجرا کنید و artifact به نام TelegramNews-A54 را دانلود کنید.

اگر Firebase به اپلیکیشن وصل نشده باشد، دریافت و تازه‌سازی اخبار در زمان باز بودن برنامه کار می‌کند، اما اعلان فوری موقع بسته‌بودن برنامه فعال نیست. سرور خبرهای قدیمی پیش از اتصال ربات را وارد نمی‌کند. برای خواندن و نوشتن D1 و درخواست‌های Worker سقف استفاده رایگان وجود دارد.

منابع رسمی: https://developers.cloudflare.com/workers/ci-cd/builds/ و https://developers.cloudflare.com/d1/get-started/ و https://core.telegram.org/bots/api
