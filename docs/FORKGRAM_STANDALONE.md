# Forkgram — standalone Android APK

This branch is based on the last unchanged four-tab Gozar release, **not** on the experimental Gozar/Forkgram combined-app integration. It checks out the pinned upstream Forkgram source at `third_party/forkgram` and builds **only** the upstream `:TMessagesProj_App:assembleAfatRelease` target. There is no Flutter host, WebView, shared VPN package or Gozar integration.

Run [the standalone workflow](https://github.com/ahbe0911-cmd/TelegramNews/actions/workflows/forkgram-standalone.yml) on branch `feature/forkgram-standalone`. Its result is a self-contained ARM64 Android APK in the Actions artifact, not a sandbox file.

For Telegram login in a custom source build, configure GitHub Actions repository secrets `FORKGRAM_APP_ID` and `FORKGRAM_APP_HASH` using **your own** API credentials. Never commit these values. When missing, CI may prove compilation but the resulting test artifact is **BUILD ONLY — NOT FOR LOGIN**. The upstream test signing key is not suitable for publishing or consistent future app updates. To distribute your own version, configure a private release keystore, keep that signing key safe across upgrades, and test sign-in, notifications, messaging, media, and network behavior on your Android phone.

If you simply need an immediately usable independent Forkgram without modifying its source, use the *upstream publisher's* separately signed official release instead of the custom CI build: https://github.com/forkgram/TelegramAndroid/releases/tag/12.10.5.1 .
