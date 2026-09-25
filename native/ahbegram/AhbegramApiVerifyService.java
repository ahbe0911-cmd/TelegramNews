package ir.channel.ahbegram;

import android.app.Service;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.Process;

import org.telegram.messenger.ApplicationLoader;
import org.telegram.messenger.BuildVars;
import org.telegram.tgnet.ConnectionsManager;
import org.telegram.tgnet.TLRPC;

import java.util.ArrayList;

/**
 * Runs in :api_verify, NOT the normal ahbegram process. Each attempt has a
 * fresh MTProto native connection because native_init freezes the API ID.
 * This service is non-exported and never writes the supplied pair to disk.
 */
public final class AhbegramApiVerifyService extends Service {
    public static final int CHECK = 1;
    public static final int RESULT = 2;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean complete;
    private final Messenger inbound = new Messenger(new Handler(
            Looper.getMainLooper(), message -> {
                if (message.what != CHECK || complete) {
                    return false;
                }
                begin(message);
                return true;
            }));

    @Override
    public IBinder onBind(Intent intent) {
        return inbound.getBinder();
    }

    private void begin(Message incoming) {
        final Messenger recipient = incoming.replyTo;
        final Bundle data = incoming.getData();
        final int id = data.getInt("id", 0);
        final String hash = data.getString("hash", "");
        if (recipient == null || id <= 0 ||
                !hash.matches("[0-9a-fA-F]{32}")) {
            finish(recipient, "invalid_format");
            return;
        }

        // Never use/build against an upstream default API key. Set the pair
        // before the FIRST native ConnectionsManager is created in this process.
        BuildVars.APP_ID = id;
        BuildVars.APP_HASH = hash;
        handler.postDelayed(() -> finish(recipient, "timeout"), 25000L);
        try {
            AhbegramApiCredentials.verifierProcessPermitted = true;
            ApplicationLoader.postInitApplication();
            TLRPC.TL_auth_exportLoginToken request =
                    new TLRPC.TL_auth_exportLoginToken();
            request.api_id = id;
            request.api_hash = hash;
            request.except_ids = new ArrayList<>();
            ConnectionsManager.getInstance(0).sendRequest(request,
                    (response, error) -> handler.post(() -> {
                        if (error != null) {
                            String text = error.text == null ? "" : error.text;
                            if (text.startsWith("API_ID_INVALID") ||
                                    text.startsWith("API_ID_PUBLISHED_FLOOD")) {
                                finish(recipient, "rejected");
                            } else if (text.startsWith("AUTH_RESTART")) {
                                finish(recipient, "try_again");
                            } else {
                                finish(recipient, "server_error");
                            }
                        } else if (response != null && (
                                response.getClass().getSimpleName()
                                        .equals("TL_auth_loginToken") ||
                                response.getClass().getSimpleName()
                                        .equals("TL_auth_loginTokenMigrateTo"))) {
                            // An actual Telegram MTProto response, not a regex
                            // check. The token is discarded: no QR is displayed.
                            finish(recipient, "verified");
                        } else {
                            finish(recipient, "server_error");
                        }
                    }), ConnectionsManager.RequestFlagWithoutLogin |
                            ConnectionsManager.RequestFlagFailOnServerErrors);
        } catch (Throwable ignored) {
            finish(recipient, "server_error");
        }
    }

    private void finish(Messenger recipient, String status) {
        if (complete) {
            return;
        }
        complete = true;
        if (recipient != null) {
            Message result = Message.obtain(null, RESULT);
            Bundle data = new Bundle();
            data.putString("status", status);
            result.setData(data);
            try {
                recipient.send(result);
            } catch (android.os.RemoteException ignored) {
                // The initiating activity went away; do not persist anything.
            }
        }
        handler.postDelayed(() -> {
            stopSelf();
            // The next trial MUST start a fresh process with a fresh native ID.
            Process.killProcess(Process.myPid());
        }, 850L);
    }
}
