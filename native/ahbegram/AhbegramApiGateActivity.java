package ir.channel.ahbegram;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.telegram.ui.LaunchActivity;

/**
 * This is the initial user-facing launcher. Local regex checks NEVER unlock
 * the phone screen: the separate :api_verify process must receive a real
 * auth.exportLoginToken response from Telegram.
 */
public final class AhbegramApiGateActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper(),
            message -> {
                if (message.what == AhbegramApiVerifyService.RESULT) {
                    deliver(message.getData().getString("status", "server_error"));
                    return true;
                }
                return false;
            });
    private final Messenger receiver = new Messenger(handler);
    private EditText idField;
    private EditText hashField;
    private TextView status;
    private Button verify;
    private Messenger remote;
    private boolean bound;
    private boolean busy;
    private int candidateId;
    private String candidateHash;

    private final ServiceConnection service = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName component, IBinder binder) {
            remote = new Messenger(binder);
            Message request = Message.obtain(null, AhbegramApiVerifyService.CHECK);
            Bundle payload = new Bundle();
            payload.putInt("id", candidateId);
            payload.putString("hash", candidateHash);
            request.setData(payload);
            request.replyTo = receiver;
            try {
                remote.send(request);
            } catch (RemoteException ignored) {
                deliver("server_error");
            }
        }

        @Override
        public void onServiceDisconnected(ComponentName component) {
            remote = null;
            if (busy) {
                deliver("server_error");
            }
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        if (AhbegramApiCredentials.isConfigured(this)) {
            next();
            return;
        }
        showSetup();
    }

    private TextView text(String value, int size, int color) {
        TextView label = new TextView(this);
        label.setText(value);
        label.setTextSize(size);
        label.setTextColor(color);
        label.setGravity(Gravity.CENTER);
        label.setPadding(10, 8, 10, 8);
        return label;
    }

    private void showSetup() {
        final int navy = Color.rgb(22, 32, 55);
        ScrollView scrolling = new ScrollView(this);
        scrolling.setFillViewport(true);
        scrolling.setBackgroundColor(Color.WHITE);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setGravity(Gravity.CENTER);
        layout.setPadding(32, 30, 32, 30);
        scrolling.addView(layout);
        setContentView(scrolling);

        ImageView icon = new ImageView(this);
        icon.setImageResource(org.telegram.messenger.R.mipmap.ic_launcher);
        int side = (int) (104 * getResources().getDisplayMetrics().density);
        layout.addView(icon, new LinearLayout.LayoutParams(side, side));
        layout.addView(text("ahbegram", 28, navy));
        layout.addView(text("مرحله ۱ از ۲ — بررسی شناسه برنامه", 17, navy));
        layout.addView(text(
                "API ID و API Hash اختصاصی خود را وارد کنید. تا وقتی سرور تلگرام تأیید نکند، مرحله شماره تلفن باز نمی‌شود.",
                14, Color.DKGRAY));

        idField = new EditText(this);
        idField.setHint("API ID");
        idField.setSingleLine(true);
        idField.setInputType(InputType.TYPE_CLASS_NUMBER);
        idField.setTextDirection(View.TEXT_DIRECTION_LTR);
        layout.addView(idField, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        hashField = new EditText(this);
        hashField.setHint("API Hash");
        hashField.setSingleLine(true);
        hashField.setInputType(InputType.TYPE_CLASS_TEXT |
                InputType.TYPE_TEXT_VARIATION_PASSWORD);
        hashField.setTextDirection(View.TEXT_DIRECTION_LTR);
        layout.addView(hashField, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        verify = new Button(this);
        verify.setText("استعلام واقعی و ادامه");
        verify.setOnClickListener(v -> verifyPair());
        layout.addView(verify, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView help = text("دریافت API ID و API Hash از my.telegram.org", 13,
                Color.rgb(38, 105, 210));
        help.setOnClickListener(v -> startActivity(new Intent(Intent.ACTION_VIEW,
                Uri.parse("https://my.telegram.org"))));
        layout.addView(help);

        status = text("", 14, Color.rgb(145, 38, 47));
        layout.addView(status);
    }

    private void verifyPair() {
        if (busy) return;
        String rawId = idField.getText().toString().trim();
        String hash = hashField.getText().toString().trim();
        final int id;
        try {
            id = Integer.parseInt(rawId);
            if (id <= 0 || !hash.matches("[a-fA-F0-9]{32}")) {
                throw new NumberFormatException();
            }
        } catch (NumberFormatException invalid) {
            status.setText("فرمت شناسه یا هش درست نیست؛ هنوز از سرور استعلامی نگرفته‌ایم.");
            return;
        }
        candidateId = id;
        candidateHash = hash;
        busy = true;
        verify.setEnabled(false);
        status.setText("در حال استعلام از سرور تلگرام…");
        Intent probe = new Intent(this, AhbegramApiVerifyService.class);
        try {
            bound = bindService(probe, service, Context.BIND_AUTO_CREATE);
            if (!bound) deliver("server_error");
        } catch (RuntimeException error) {
            deliver("server_error");
        }
    }

    private void deliver(String code) {
        if (!busy) return;
        busy = false;
        candidateHash = null;
        if (bound) {
            try {
                unbindService(service);
            } catch (IllegalArgumentException ignored) { }
            bound = false;
        }
        remote = null;
        if ("verified".equals(code)) {
            String pair = hashField.getText().toString().trim();
            try {
                // Only this real server-backed result unlocks the phone stage.
                AhbegramApiCredentials.saveVerified(this, candidateId, pair);
                hashField.getText().clear();
                next();
                return;
            } catch (java.security.GeneralSecurityException failure) {
                status.setText("ذخیره امن API امکان‌پذیر نیست؛ دوباره تلاش کنید.");
            }
        } else if ("rejected".equals(code)) {
            status.setText("تلگرام این API ID / API Hash را نپذیرفت. اطلاعات را اصلاح کنید.");
        } else if ("timeout".equals(code)) {
            status.setText("پاسخ سرور نرسید. اینترنت یا پروکسی را بررسی و دوباره تلاش کنید.");
        } else if ("invalid_format".equals(code)) {
            status.setText("فرمت مقادیر نادرست است.");
        } else {
            status.setText("تأیید از سرور انجام نشد؛ فعلاً اجازه ورود به مرحله شماره وجود ندارد.");
        }
        // Give the old isolated MTProto process time to exit before a retry.
        handler.postDelayed(() -> {
            if (!isFinishing() && verify != null) verify.setEnabled(true);
        }, 1100L);
    }

    private void next() {
        startActivity(new Intent(this, LaunchActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP));
        finish();
    }

    @Override
    protected void onDestroy() {
        if (bound) {
            try {
                unbindService(service);
            } catch (IllegalArgumentException ignored) { }
        }
        candidateHash = null;
        super.onDestroy();
    }
}
