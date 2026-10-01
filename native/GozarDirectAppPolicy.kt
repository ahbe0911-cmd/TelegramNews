package ir.channel.telegram_news

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager

/**
 * Packages that should stay on the device's direct network while the VPN is on.
 * This keeps Iranian banking/payment apps and the requested local messengers
 * usable without asking the user to maintain a per-app list.
 */
object GozarDirectAppPolicy {
    private val exactPackages = setOf(
        "app.rbmain.a",
        "ir.nasim",
        "ir.eitaa.messenger",
        "ir.medu.shad",
        "ir.medu.shad.mobile"
    )

    private val packageHints = listOf(
        "rubika",
        "eitaa",
        ".shad",
        "bankmellat",
        "bankmelli",
        "bankmeli",
        "tejaratbank",
        "banktejarat",
        "banksaderat",
        "banksepah",
        "bankmaskan",
        "bankrefah",
        "bankshahr",
        "bankpasargad",
        "parsianbank",
        "samanbank",
        "resalat",
        "eghtesadnovin",
        "blubank",
        "wepod",
        "sadad",
        "asanpardakht",
        "behpardakht"
    )

    private val bankingLabelHints = listOf(
        "بانک",
        "همراه بانک",
        "موبایل بانک",
        "بلوبانک",
        "بلو بانک",
        "ویپاد",
        "همراه کارت",
        "ایوا",
        "سکه",
        "۷۲۴"
    )

    private val exactLocalLabels = setOf(
        "روبیکا",
        "بله",
        "ایتا",
        "شاد",
        "آپ",
        "تاپ"
    )

    @Suppress("DEPRECATION")
    private fun installedApplications(
        packageManager: PackageManager
    ): List<ApplicationInfo> =
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            packageManager.getInstalledApplications(
                PackageManager.ApplicationInfoFlags.of(0L)
            )
        } else {
            packageManager.getInstalledApplications(0)
        }

    fun installedPackages(
        packageManager: PackageManager,
        selfPackage: String
    ): List<String> {
        val output = LinkedHashSet<String>()

        for (info in installedApplications(packageManager)) {
            val pkg = info.packageName ?: continue
            if (pkg == selfPackage) continue

            val lowerPackage = pkg.lowercase()
            val label = try {
                packageManager.getApplicationLabel(info)
                    .toString()
                    .trim()
            } catch (_: Throwable) {
                ""
            }
            val lowerLabel = label.lowercase()

            val isFinance =
                info.category == ApplicationInfo.CATEGORY_FINANCE
            val exactLocal =
                exactPackages.contains(pkg) ||
                    exactLocalLabels.contains(label)
            val packageMatched =
                packageHints.any { lowerPackage.contains(it) }
            val labelMatched =
                bankingLabelHints.any { lowerLabel.contains(it) }

            if (isFinance ||
                exactLocal ||
                packageMatched ||
                labelMatched) {
                output += pkg
            }
        }

        return output.toList()
    }
}
