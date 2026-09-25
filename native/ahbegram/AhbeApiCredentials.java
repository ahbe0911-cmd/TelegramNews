package org.telegram.messenger;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * User-supplied API credentials for this independent client. Never log them,
 * write them to a GitHub build, or treat a local format check as verification.
 * The hash is an application credential (not the user's Telegram password).
 *
 * MODE_PRIVATE limits access on an ordinary Android installation. Production
 * distribution should additionally migrate this to Android Keystore-backed
 * encryption; do not export the app's private preferences in backups.
 */
public final class AhbeApiCredentials {
    private static final String PREFS = "ahbe_api_credentials";
    private static final String KEY_ID = "api_id";
    private static final String KEY_HASH = "api_hash";
    private static final String KEY_VERIFIED = "server_verified";
    private AhbeApiCredentials() {}

    public static boolean hasVerified(Context context) {
        if (context == null) return false;
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        return prefs.getBoolean(KEY_VERIFIED, false)
            && prefs.getInt(KEY_ID, 0) > 0
            && prefs.getString(KEY_HASH, "").matches("(?i)[a-f0-9]{32}");
    }

    public static int readId(Context context) {
        return hasVerified(context)
            ? context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getInt(KEY_ID, 0)
            : 0;
    }

    public static String readHash(Context context) {
        return hasVerified(context)
            ? context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_HASH, "")
            : "";
    }

    public static void storeVerified(Context context, int id, String hash) {
        if (id <= 0 || hash == null || !hash.matches("(?i)[a-f0-9]{32}")) {
            throw new IllegalArgumentException("Invalid API credential format");
        }
        if (!context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putInt(KEY_ID, id).putString(KEY_HASH, hash)
            .putBoolean(KEY_VERIFIED, true).commit()) {
            throw new IllegalStateException("Unable to store API credentials");
        }
    }
}
