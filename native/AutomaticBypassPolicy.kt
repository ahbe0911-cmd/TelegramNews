package ir.channel.telegram_news

import android.content.Intent
import android.content.pm.PackageManager

/**
 * Apps that must keep the phone's direct connection while the full-device VPN
 * is active. Detection is based on installed launcher labels and conservative
 * package-name hints so it also works across bank app updates.
 */
internal object AutomaticBypassPolicy {
    private val packageHints = listOf(
        "rubika", ".bale", "bale.", ".bank", "bank.",
        "mobilebank", "hamrahbank"
    )

    private fun shouldBypass(label: String, packageName: String): Boolean {
        val normalizedLabel = label.trim().lowercase()
            .replace("\u200c", " ")
            .replace(Regex("\\s+"), " ")
        val normalizedPackage = packageName.lowercase()
        val isBank = normalizedLabel.contains("بانک") ||
            normalizedLabel.contains("bank") ||
            packageHints.drop(2).any { normalizedPackage.contains(it) }
        val isRubika = normalizedLabel == "روبیکا" ||
            normalizedLabel.contains("rubika") ||
            normalizedPackage.contains("rubika")
        val isBale = normalizedLabel == "بله" ||
            normalizedLabel.contains("پیام رسان بله") ||
            normalizedLabel.contains("پیام‌رسان بله") ||
            normalizedPackage.contains(".bale") ||
            normalizedPackage.contains("bale.")
        return isBank || isRubika || isBale
    }

    fun installedPackages(
        packageManager: PackageManager,
        selfPackage: String
    ): List<String> {
        val launcher = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(launcher, 0)
            .mapNotNull { info ->
                val pkg = info.activityInfo.packageName
                val label = info.loadLabel(packageManager).toString()
                if (pkg == selfPackage || !shouldBypass(label, pkg)) null else pkg
            }
            .distinct()
            .sorted()
    }
}
