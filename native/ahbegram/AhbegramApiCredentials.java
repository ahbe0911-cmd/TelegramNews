package ir.channel.ahbegram;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import org.telegram.messenger.BuildVars;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyStore;
import java.util.regex.Pattern;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Stores the user's server-checked API pair locally. Never back up, print,
 * send to the app's analytics, or place these values in Intents.
 *
 * A restored encrypted preferences file without its Android Keystore key is
 * deliberately treated as unconfigured; the user must re-enter the pair.
 */
public final class AhbegramApiCredentials {
    private static final String PREFS = "ahbegram_api_credentials";
    private static final String KEY_ALIAS = "ahbegram_api_hash_aes_gcm_v1";
    private static final Pattern HASH = Pattern.compile("[0-9a-fA-F]{32}");

    private AhbegramApiCredentials() { }

    private static SharedPreferences prefs(Context context) {
        return context.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static SecretKey key() throws GeneralSecurityException {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        SecretKey existing = (SecretKey) store.getKey(KEY_ALIAS, null);
        if (existing != null) {
            return existing;
        }
        KeyGenerator generator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build());
        return generator.generateKey();
    }

    private static String savedHash(Context context, int id)
            throws GeneralSecurityException {
        SharedPreferences stored = prefs(context);
        String ciphertext = stored.getString("secret", null);
        String nonce = stored.getString("nonce", null);
        if (id <= 0 || ciphertext == null || nonce == null) {
            return null;
        }
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128,
                Base64.decode(nonce, Base64.NO_WRAP)));
        cipher.updateAAD(Integer.toString(id).getBytes(StandardCharsets.US_ASCII));
        byte[] plain = cipher.doFinal(Base64.decode(ciphertext, Base64.NO_WRAP));
        String hash = new String(plain, StandardCharsets.US_ASCII);
        return HASH.matcher(hash).matches() ? hash : null;
    }

    public static boolean isConfigured(Context context) {
        SharedPreferences stored = prefs(context);
        if (!stored.getBoolean("server_checked", false)) {
            return false;
        }
        try {
            return savedHash(context, stored.getInt("id", 0)) != null;
        } catch (GeneralSecurityException | IllegalArgumentException error) {
            return false;
        }
    }

    /** Must be called before creating any ConnectionsManager in the main process. */
    public static void applySaved(Context context) {
        SharedPreferences stored = prefs(context);
        if (!stored.getBoolean("server_checked", false)) {
            return;
        }
        int id = stored.getInt("id", 0);
        try {
            String hash = savedHash(context, id);
            if (hash != null) {
                BuildVars.APP_ID = id;
                BuildVars.APP_HASH = hash;
            }
        } catch (GeneralSecurityException | IllegalArgumentException ignored) {
            // Never fall back to a public upstream API pair silently.
        }
    }

    public static void saveVerified(Context context, int id, String hash)
            throws GeneralSecurityException {
        if (id <= 0 || hash == null || !HASH.matcher(hash).matches()) {
            throw new GeneralSecurityException("Invalid API credential format");
        }
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key());
        cipher.updateAAD(Integer.toString(id).getBytes(StandardCharsets.US_ASCII));
        byte[] ciphertext = cipher.doFinal(hash.getBytes(StandardCharsets.US_ASCII));
        if (!prefs(context).edit()
                .putInt("id", id)
                .putString("nonce", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
                .putString("secret", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
                .putBoolean("server_checked", true)
                .commit()) {
            throw new GeneralSecurityException("Cannot save the checked API pair");
        }
        BuildVars.APP_ID = id;
        BuildVars.APP_HASH = hash;
    }
}
