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

## راه‌اندازی کانال خصوصی روی ورکر موجود

نیازی به ساخت Worker یا دیتابیس جدید ندارید. نسخه جدید فایل worker/src/index.mjs را در همان Worker با نام still-morning-ed74 داخل Edit code جایگزین و Deploy کنید. تغییر کد در GitHub به‌تنهایی ورکر موجود را به‌روزرسانی نمی‌کند، مگر استقرار خودکار از GitHub را جداگانه فعال کرده باشید.

۱. ربات را مدیر کانال نگه دارید؛ سپس کانال را خصوصی کنید.
۲. Cloudflare → still-morning-ed74 → Observability → Logs، نمایش لاگ‌های زنده را فعال کنید.
۳. یک پیام **جدید** در کانال خصوصی منتشر کنید. کد به‌روزشده پس از دریافت وب‌هوک معتبر خط `Channel ID for setup: -100...` را در لاگ نمایش می‌دهد؛ محتوای خبر یا توکن را ثبت نمی‌کند. این شناسه عددی را یادداشت کنید. اگر این خط دیده نشد، ثبت صحیح Secret، استقرار آخرین کد و لاگ درخواست‌های ورودی را بررسی کنید.
۴. از Settings → Variables and Secrets، مقدار متغیر متنی `TELEGRAM_CHANNEL_ID` را برابر **همان شناسه کامل، شامل -100 ابتدای آن** قرار دهید. آن را به‌عنوان Secret هم می‌توانید نگه دارید، اما کد باید این نام را به‌عنوان متغیر دریافت کند. Save/Deploy کنید.
۵. خبر **تازه** دیگری در کانال منتشر کنید و مسیر `/posts` را باز کنید. در صورت صحیح بودن اتصال، عنوان خبر در JSON نمایش داده می‌شود. لینک `t.me/c/...` برای نمایش داخل تلگرام تنها برای کاربران دارای دسترسی به کانال قابل استفاده است.

هشدار: مسیرهای `/posts` و `/image` همچنان عمومی هستند. خصوصی کردن کانال فقط دسترسی در تلگرام را کنترل می‌کند و به‌خودی‌خود اخبار ذخیره‌شده در API یا APK را تنها به اعضا محدود نمی‌کند. برای دسترسی اعضا باید احراز هویت کاربر و کنترل عضویت را به بک‌اند اضافه کرد. اگر محتوا محرمانه است، **تا تکمیل کنترل دسترسی آن را در این نسخه از ورکر منتشر نکنید**.
