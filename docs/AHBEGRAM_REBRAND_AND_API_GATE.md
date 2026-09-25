# ahbegram — standalone Android client (implementation specification)

Status: design/research branch only. **Do not release the previous Forkgram CI APK as ahbegram.**
Base: pinned upstream Forkgram at `third_party/forkgram`, kept independently from Gozar.
Requested visible identity: `ahbegram`; use the exact user-supplied blue-to-purple speech-mark logo as the canonical artwork, not the upstream paper-plane or Forkgram launcher assets.

## Runtime API credential gate

For **a new, not-yet-authorized installation**, the first foreground screen is the ahbegram onboarding screen with API ID and API Hash fields, a link to https://my.telegram.org (API development tools), and an explicit Verify button. It must not ask for a phone number before the server-backed preflight is successful. On later runs, skip onboarding only if a previously validated pair is present.

Validation needs **three distinct outcomes**:
1. Local syntax checks: numeric positive API ID, 32 hexadecimal characters in API Hash. Passing only this step must NEVER be reported as server verification.
2. Make an actual unauthenticated MTProto `auth.exportLoginToken(api_id,api_hash,except_ids=[])` request using the supplied pair. Treat a real `auth.loginToken` result as successful preflight; treat `API_ID_INVALID` / `API_ID_PUBLISHED_FLOOD` as credential rejection; treat timeout/network/proxy/other API policy errors separately. Do not silently substitute a hard-coded upstream API pair. This operation requests an ephemeral login token; do not display a QR or authorize a user from this preflight.
3. During phone-based authentication, `auth.sendCode` independently checks the pair with the supplied phone number. Recheck and surface its server errors. Preflight alone cannot guarantee that this later step will succeed.

**Native initialization guard:** Upstream `BuildVars.APP_ID` and `APP_HASH` come from build-time `BuildConfig`, and `ConnectionsManager` freezes the API ID in the native network engine on first instance initialization. A verifier must not simply update BuildVars and retry against an already-created singleton with the old ID. Use an isolated, non-exported process for individual preflight attempts, keep the credentials out of logs, then initialize the primary app process with the validated saved pair **before** any ConnectionsManager is constructed. Guard the upstream LaunchActivity, deep-links, notifications, shares and alternative account/login routes; do not allow any entry point to skip first-run credential onboarding. Never persist credentials as verified after syntax checks or an unhandled server error. Protect local credential storage with Android Keystore-backed encryption and permit explicit credential reset only after logout / clear account state to avoid breaking existing sessions.

## Visible identity changes and source boundary

Set a *unique* Android application ID (such as `ir.channel.ahbegram`, subject to owner approval), package label, installer icon and round/adaptive icon, app launcher aliases, splash artwork, in-app app title, own notifications and shortcuts to **ahbegram**. Keep the exact provided artwork unchanged except for standard crop/resampling for launcher icon sizes. Build must fail if exact asset is missing; never silently fall back to upstream icon. Audit upstream upgrade/rebrand regression.

Do NOT globally replace/remove every occurrence of the word Telegram. Keep upstream source packages/classes, MTProto schema, `tg://` deep links, Telegram service endpoints, required legal/license notices, acknowledgments, and factual explanations such as "login code was sent to your Telegram app". Replacing these would break interoperability or conceal which service the client uses. Do not imply this is the official Telegram client.

## Acceptance tests before an installable APK is announced

- First run requires API pair; server rejects a purposely invalid ID **before** phone screen; offline/proxy errors must not be misreported as invalid credentials.
- Valid pair preflight advances to phone input, then real code delivery and sign-in succeed. Re-launch retains validated pair without re-prompting. Editing a rejected pair must use a fresh native validation context.
- All Android entry points obey the credential gate. API values never appear in logs, screenshots, source commits, repository artifacts, analytics, exported intents or clipboard.
- Launcher label/icon/round and adaptive icon, splash screen, shortcuts, notification title and user-facing branding use ahbegram; open-source attributions and necessary Telegram references remain.
- ARM64 APK compiles and is installed/tested on device for messaging, media, proxy access, background notifications and update signing.

The old standalone workflow produces an **upstream** test-signed package with no personal API credentials; it does not implement these requirements. This feature branch is not a completed APK.
