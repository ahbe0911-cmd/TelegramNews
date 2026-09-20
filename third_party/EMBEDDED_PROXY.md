# In-app TG WS Proxy (Android A54)

Both application variants embed the same pinned native Kotlin engine from
crim50n/tg-ws-proxy-android at commit ee7669947090dd55da0f20663bc7a2abd3c5288e
under its MIT license, preserved in third_party/TG-WS-PROXY-LICENSE.txt.

The on-device listener runs in the app process on 127.0.0.1. News uses port
17443 and Cafenet 17444; the default upstream TG WS Proxy uses port 1443.
Each variant independently generates and persists its own 16-byte secret.
Dart enables proxyTypeMtproto through TDLib before fetching authorization
state. A Settings switch can disable or re-enable the embedded relay.

No remote server is bundled and there is no guarantee that WS, Cloudflare or
direct TCP can reach Telegram from any given network. Listener readiness
does NOT imply remote connectivity. Unlike the standalone upstream app this
integration has no Android foreground service: if Android kills the news
app process the local listener stops. Opening the app starts it again.

SECURITY: upstream RawWebSocket deliberately relaxes TLS certificate
verification for IP-redirection routes. This integration retains that upstream
behavior, which is not equivalent to certificate-verified HTTPS. Assess
this risk before distributing the APKs to other users.

The release workflow checks out this precise source revision, runs
scripts/embed_ws_proxy.py after generating Android host, then runs Flutter
tests and APK identity verification for each APK independently.
