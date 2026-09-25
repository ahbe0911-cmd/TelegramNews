/*
 * Same-package bottom navigation wrapping the ORIGINAL Forkgram LaunchActivity
 * content tree. This file is copied into the upstream TMessagesProj library at
 * build time; upstream source is NOT modified in Git.
 *
 * Only call from LaunchActivity after frameLayout is created. Never replace
 * Forkgram's frameLayout with a WebView or a second, separately installed APK.
 */
package ir.channel.telegram_news;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

public final class GozarForkgramTabShell {
    private GozarForkgramTabShell() { }

    private static int dp(Activity activity, int value) {
        return Math.round(value * activity.getResources().getDisplayMetrics().density);
    }

    /**
     * Hosts the unmodified Telegram chat frame in the top, weighted content
     * area and allocates a REAL native bar for Gozar along the bottom.
     */
    public static View wrap(Activity activity, View telegramContent) {
        LinearLayout column = new LinearLayout(activity);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setBackgroundColor(Color.WHITE);
        column.addView(telegramContent, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        LinearLayout navigation = new LinearLayout(activity);
        navigation.setGravity(Gravity.CENTER);
        navigation.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        navigation.setBackgroundColor(Color.WHITE);
        navigation.setElevation(dp(activity, 5));
        navigation.setMinimumHeight(dp(activity, 68));

        final String[] labels = {"خانه", "تلگرام", "لانچر", "یادداشت", "تنظیمات"};
        for (int i = 0; i < labels.length; i++) {
            final int tab = i;
            TextView item = new TextView(activity);
            item.setGravity(Gravity.CENTER);
            item.setText(labels[i]);
            item.setSingleLine(true);
            item.setTextSize(11);
            item.setTypeface(Typeface.DEFAULT, tab == 1 ? Typeface.BOLD : Typeface.NORMAL);
            item.setTextColor(tab == 1 ? Color.rgb(10, 95, 149) : Color.rgb(76, 91, 107));
            if (tab == 1) {
                GradientDrawable selected = new GradientDrawable();
                selected.setColor(Color.rgb(211, 237, 255));
                selected.setCornerRadius(dp(activity, 18));
                item.setBackground(selected);
            } else {
                item.setOnClickListener(view -> {
                    Intent intent = new Intent();
                    intent.setClassName(activity.getPackageName(),
                        "ir.channel.telegram_news.MainActivity");
                    intent.putExtra("gozar_target_tab", tab);
                    intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP
                        | Intent.FLAG_ACTIVITY_SINGLE_TOP);
                    activity.startActivity(intent);
                });
            }
            navigation.addView(item, new LinearLayout.LayoutParams(
                0, dp(activity, 52), 1f));
        }
        column.addView(navigation, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(activity, 68)));
        return column;
    }
}
