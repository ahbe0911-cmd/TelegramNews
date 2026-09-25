/*
 * Integration adapter for the real Forkgram LaunchActivity.
 *
 * The source is kept OUTSIDE the pinned upstream submodule so a new Forkgram
 * release can be reviewed without losing Gozar-specific changes.
 *
 * This class MUST NOT be shipped before the host package includes both
 * the real upstream TMessagesProj and the Flutter MainActivity.
 */
package ir.channel.telegram_news;

import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.telegram.ui.LaunchActivity;

public class GozarTelegramActivity extends LaunchActivity {
    private boolean wrappingContent;

    private int dp(float amount) {
        return Math.round(amount * getResources().getDisplayMetrics().density);
    }

    /**
     * Forkgram's LaunchActivity installs its real dialogs/chats view through
     * setContentView(frameLayout). Keep that exact View alive, and attach our
     * Gozar navigation OUTSIDE the native Telegram view (not in a WebView).
     * The companion Flutter activity is in the SAME Android package/APK.
     */
    @Override
    public void setContentView(View telegramContent) {
        if (wrappingContent) {
            super.setContentView(telegramContent);
            return;
        }
        wrappingContent = true;
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setBackgroundColor(Color.WHITE);
        column.addView(telegramContent, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        LinearLayout navigation = new LinearLayout(this);
        navigation.setGravity(Gravity.CENTER);
        navigation.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        navigation.setBackgroundColor(Color.WHITE);
        navigation.setElevation(dp(5));
        navigation.setMinimumHeight(dp(68));

        final int[] destinations = {0, 1, 2, 3, 4};
        final String[] labels = {"خانه", "تلگرام", "لانچر", "یادداشت", "تنظیمات"};
        for (int i = 0; i < destinations.length; i++) {
            final int tab = destinations[i];
            TextView item = new TextView(this);
            item.setGravity(Gravity.CENTER);
            item.setText(labels[i]);
            item.setSingleLine(true);
            item.setTextSize(11);
            item.setTypeface(Typeface.DEFAULT, tab == 1 ? Typeface.BOLD : Typeface.NORMAL);
            item.setTextColor(tab == 1 ? Color.rgb(10, 95, 149) : Color.rgb(76, 91, 107));
            if (tab == 1) {
                GradientDrawable selected = new GradientDrawable();
                selected.setColor(Color.rgb(211, 237, 255));
                selected.setCornerRadius(dp(18));
                item.setBackground(selected);
            } else {
                item.setOnClickListener(view -> returnToGozarTab(tab));
            }
            navigation.addView(item, new LinearLayout.LayoutParams(0, dp(52), 1f));
        }
        column.addView(navigation, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(68)));
        super.setContentView(column);
    }

    private void returnToGozarTab(int index) {
        // No second APK, package lookup, exported intent, or app-store launch.
        Intent intent = new Intent();
        intent.setClassName(getPackageName(), "ir.channel.telegram_news.MainActivity");
        intent.putExtra("gozar_target_tab", index);
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        startActivity(intent);
    }
}
