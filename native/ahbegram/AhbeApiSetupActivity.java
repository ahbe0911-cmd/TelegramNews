package org.ahbegram;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.telegram.messenger.AhbeApiCredentials;
import org.telegram.messenger.ApplicationLoader;
import org.telegram.messenger.BuildVars;
import org.telegram.tgnet.ConnectionsManager;
import org.telegram.tgnet.TLRPC;
import org.telegram.ui.LaunchActivity;

import java.util.ArrayList;

/**
 * First-run native credentials gate, before the phone-number/QR login flow.
 *
 * Do not confuse a 32-digit hash syntax check with server verification.
 * auth.exportLoginToken sends BOTH fields to Telegram via MTProto on an
 * unauthenticated connection. We only unlock the next screen on a successful
 * auth.LoginToken result, never on a timeout or an ambiguous RPC error.
 */
public final class AhbeApiSetupActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private EditText idField;
    private EditText hashField;
    private TextView status;
    private Button verifyButton;
    private boolean pending;
    private int requestGeneration;

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private GradientDrawable rounded(int color, int radius) {
        GradientDrawable background = new GradientDrawable();
        background.setColor(color);
        background.setCornerRadius(dp(radius));
        return background;
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setGravity(Gravity.CENTER);
        view.setTypeface(Typeface.DEFAULT, bold ? Typeface.BOLD : Typeface.NORMAL);
        return view;
    }

    private EditText field(String hint, boolean secret) {
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setHint(hint);
        input.setTextSize(16);
        input.setTextColor(Color.rgb(25, 38, 63));
        input.setHintTextColor(Color.rgb(133, 145, 167));
        input.setPadding(dp(18), 0, dp(18), 0);
        input.setBackground(rounded(Color.rgb(243, 246, 253), 16));
        input.setInputType(secret
            ? InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD
            : InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        if (!secret) input.setInputType(InputType.TYPE_CLASS_NUMBER);
        return input;
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(Color.WHITE);
        getWindow().setNavigationBarColor(Color.WHITE);
        getWindow().getDecorView().setSystemUiVisibility(
            android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            | android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        if (AhbeApiCredentials.hasVerified(this)) {
            openPhoneLogin();
            return;
        }
        render();
    }

    private void render() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(Color.WHITE);
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setGravity(Gravity.CENTER_HORIZONTAL);
        column.setPadding(dp(26), dp(36), dp(26), dp(32));
        scroll.addView(column, new ScrollView.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        ImageView icon = new ImageView(this);
        icon.setImageResource(getResources().getIdentifier("ic_launcher", "mipmap", getPackageName()));
        icon.setContentDescription("ahbegram");
        icon.setScaleType(ImageView.ScaleType.FIT_CENTER);
        column.addView(icon, new LinearLayout.LayoutParams(dp(100), dp(100)));

        TextView title = text("ahbegram", 30, Color.rgb(26, 35, 65), true);
        LinearLayout.LayoutParams titleLayout = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(52));
        titleLayout.topMargin = dp(8);
        column.addView(title, titleLayout);

        TextView subtitle = text("تنظیم شناسهٔ برنامه", 19, Color.rgb(46, 55, 87), true);
        LinearLayout.LayoutParams subtitleLayout = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(45));
        subtitleLayout.topMargin = dp(20);
        column.addView(subtitle, subtitleLayout);

        TextView help = text(
            "ابتدا API ID و API Hash برنامهٔ خود را وارد کنید. " +
            "تا زمانی که سرور تلگرام آن‌ها را نپذیرد، مرحلهٔ شمارهٔ تلفن باز نمی‌شود.",
            14, Color.rgb(104, 116, 141), false);
        help.setLineSpacing(dp(4), 1f);
        column.addView(help, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(100)));

        idField = field("API ID", false);
        LinearLayout.LayoutParams idLayout = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(56));
        idLayout.topMargin = dp(18);
        column.addView(idField, idLayout);

        hashField = field("API Hash (۳۲ کاراکتر)", true);
        LinearLayout.LayoutParams hashLayout = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(56));
        hashLayout.topMargin = dp(12);
        column.addView(hashField, hashLayout);

        status = text("اتصال برای اعتبارسنجی به اینترنت نیاز دارد.", 13,
            Color.rgb(104, 116, 141), false);
        LinearLayout.LayoutParams statusLayout = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(74));
        column.addView(status, statusLayout);

        verifyButton = new Button(this);
        verifyButton.setAllCaps(false);
        verifyButton.setText("بررسی از سرور و ادامه");
        verifyButton.setTextColor(Color.WHITE);
        verifyButton.setTextSize(16);
        verifyButton.setBackground(rounded(Color.rgb(54, 88, 222), 18));
        verifyButton.setOnClickListener(view -> verify());
        column.addView(verifyButton, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(56)));
        setContentView(scroll);
    }

    private void message(String text, boolean error) {
        status.setText(text);
        status.setTextColor(error ? Color.rgb(191, 57, 77) : Color.rgb(54, 88, 170));
    }

    private void busy(boolean state) {
        pending = state;
        verifyButton.setEnabled(!state);
        idField.setEnabled(!state);
        hashField.setEnabled(!state);
        verifyButton.setText(state ? "در حال بررسی ارتباط با سرور…" : "بررسی از سرور و ادامه");
    }

    private void verify() {
        if (pending) return;
        String idText = idField.getText().toString().trim();
        String hash = hashField.getText().toString().trim();
        int id;
        try {
            id = Integer.parseInt(idText);
        } catch (NumberFormatException ignored) {
            message("API ID باید یک عدد صحیح معتبر باشد.", true);
            return;
        }
        if (id <= 0 || !hash.matches("(?i)[a-f0-9]{32}")) {
            message("API ID یا قالب API Hash صحیح نیست.", true);
            return;
        }

        busy(true);
        message("در حال دریافت پاسخ واقعی از سرور تلگرام…", false);
        final int generation = ++requestGeneration;
        // Forkgram's ApplicationLoader is initialized normally by the native
        // application; its MTProto connection is brought up only after the user
        // supplies candidate credentials. The API request below supplies both
        // fields explicitly and does not request a phone verification code.
        BuildVars.APP_ID = id;
        BuildVars.APP_HASH = hash;
        try {
            ApplicationLoader.postInitApplication();
            TLRPC.TL_auth_exportLoginToken request = new TLRPC.TL_auth_exportLoginToken();
            request.api_id = id;
            request.api_hash = hash;
            request.except_ids = new ArrayList<>();
            ConnectionsManager.getInstance(0).sendRequest(request, (response, error) ->
                runOnUiThread(() -> {
                    if (generation != requestGeneration || isFinishing()) return;
                    busy(false);
                    if (error != null) {
                        final String code = error.text == null ? "" : error.text;
                        if (code.contains("API_ID_INVALID")
                            || code.contains("API_ID_PUBLISHED_FLOOD")) {
                            message("سرور این شناسه یا هش را نپذیرفت. اطلاعات را بررسی کنید.", true);
                        } else {
                            // Network, flood and transient server failures are
                            // not proof that the user's hash is invalid.
                            message("سرور تأیید نکرد (" + code + "). دوباره تلاش کنید.", true);
                        }
                        return;
                    }
                    if (!(response instanceof TLRPC.TL_auth_loginToken)
                        && !(response instanceof TLRPC.TL_auth_loginTokenMigrateTo)
                        && !(response instanceof TLRPC.TL_auth_loginTokenSuccess)) {
                        message("پاسخ سرور برای تأیید کافی نبود. دوباره تلاش کنید.", true);
                        return;
                    }
                    try {
                        AhbeApiCredentials.storeVerified(this, id, hash);
                        message("شناسهٔ برنامه توسط سرور پذیرفته شد.", false);
                        openPhoneLogin();
                    } catch (RuntimeException ignored) {
                        message("ذخیره‌سازی تنظیمات ممکن نشد؛ دوباره تلاش کنید.", true);
                    }
                }), ConnectionsManager.RequestFlagFailOnServerErrors
                    | ConnectionsManager.RequestFlagWithoutLogin);
        } catch (RuntimeException error) {
            busy(false);
            message("راه‌اندازی اتصال ممکن نشد. اتصال اینترنت را بررسی کنید.", true);
        }
        handler.postDelayed(() -> {
            if (generation == requestGeneration && pending && !isFinishing()) {
                requestGeneration++;
                busy(false);
                message("پاسخی دریافت نشد. شبکه یا پروکسی را بررسی و دوباره تلاش کنید.", true);
            }
        }, 30000L);
    }

    private void openPhoneLogin() {
        Intent intent = new Intent(this, LaunchActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        startActivity(intent);
        finish();
    }

    @Override
    protected void onDestroy() {
        requestGeneration++;
        super.onDestroy();
    }
}
