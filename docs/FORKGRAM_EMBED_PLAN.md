# Forkgram inside Gozar — integration workspace (NOT shipping)

## Requested product
Replace the removed «شبکه» destination with «تلگرام». This must display the
full native Forkgram conversation UI **inside the same Gozar application**,
with the same Flutter bottom navigation. Opening a separately installed APK,
a URL, a WebView imitation, or a static placeholder does NOT satisfy this goal.

## Current state (2026-09-24)
- The stable Gozar branch `three-independent-apps` is unchanged.
- `third_party/forkgram` is a true Git submodule of the official
  `https://github.com/forkgram/TelegramAndroid.git` upstream, pinned to
  upstream release `12.10.5.1` at
  `4992e612cfc99b1e967722822c1c4eb7aafe516b`.
- Submodule == FULL SOURCE CHECKOUT WHEN INITIALIZED, not an Android library
  and not a working Gozar tab. No new APK or embedded Telegram UI exists yet.

## Why merely cloning does not embed the app
Forkgram is a **standalone native Android application** with a very large
`org.telegram.ui.LaunchActivity`, its own `ApplicationLoaderImpl`,
application manifest, Android resource set, native C/C++ libraries,
notification and background services. Gozar is a Flutter app with a separate
Android host, VPN lifecycle, Android manifest and a fixed bottom navigation.
Android does not natively render a foreign full-screen Activity as a regular
Flutter tab. Do not use Activity launch + hide Gozar as a purported embed.

Required integration work on this *isolated* branch:
1. Build unmodified upstream release and its recursive Git submodules in a
   capable Android 36 / NDK 27c / Java 21 (see upstream BUILDING.md), after
   supplying own Telegram API ID/hash via secure build secrets.
2. Select a host architecture and prove a functioning native Telegram
   dialog **view** hosted in Gozar, including login, real messages and
   navigation without an additional launcher app. One option is adapting
   Forkgram's native navigation into a reusable embedded native screen and
   exposing it to Flutter through PlatformView; another is making Forkgram
   the Android host and embedding Flutter modules. Both require invasive
   source/build changes and cannot be treated as a one-line import.
3. Reconcile manifest, Application, background services, file sharing,
   push notifications, media access, account separation, lifecycle,
   window insets, Android back navigation, audio/video, and JNI dependencies.
   Never share VPN/profile secrets or auto-import a separately installed
   Forkgram login.
4. Handle Gozar's VPN self-UID exclusion: embedding Forkgram in the same
   Android package gives it the same UID, which is **not automatically tunneled**
   through Gozar's own VPN. Verify Telegram network routing on-device;
   consider Telegram's native proxy configuration if appropriate. Do not
   claim that embedding automatically solves VPN routing.
5. Only after a real embedded view passes device tests, add the destination
   `خانه | تلگرام | لانچر | یادداشت | تنظیمات`, remap notes/settings indices,
   and verify all old features before merging into the stable branch.

## Updating upstream without breaking Gozar
The Git submodule keeps upstream and local adapter code separate.
`scripts/check_forkgram_update.sh` resolves the latest published upstream
release and updates the submodule pin on a **dedicated bot branch**, then opens
a review PR aimed at this integration branch. Manual or scheduled use of
`.github/workflows/forkgram-upstream-check.yml` requires its workflow to
be present on GitHub's default branch for scheduled runs to become active.
It is NOT active merely because it exists in this feature branch. No bot
automatically merges untested native code or updates an installed APK.

A new upstream release requires: inspect upstream changes, adapt the Gozar
integration layer, build the combined signed APK, run automated AND actual
phone tests (login, dialogs, downloads, notifications, VPN, launcher, notes),
and install the new APK with the SAME release signing certificate.
Do not automatically update an in-use APK from an external release APK.

## Licensing and API credentials
Upstream is GNU GPL-2.0 (see its LICENSE); keep notices, applicable license,
source availability for distributed derivatives, and comply with third-party
dependencies. Forkgram's BUILDING.md requires using your own Telegram API
ID/hash for modified versions. Do not commit credentials, keystores, session
tokens, or generated binaries into the public repository.

## Source reference
https://github.com/forkgram/TelegramAndroid
https://github.com/forkgram/TelegramAndroid/blob/dev/BUILDING.md
