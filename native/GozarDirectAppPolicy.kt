package ir.channel.telegram_news

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager

/**
 * Packages that should stay on the device's direct network while VPN is on.
 * Detection is deliberately local: known Iranian messenger package/labels,
 * banking/payment product labels, and package-name hints.
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
        "bank",
        "mellat",
        "melli",
        "bmi.",
        ".bmi",
        "bsi.",
        ".bsi",
        "tejarat",
        "saderat",
        "sepah",
        "maskan",
        "refah",
        "shahr",
        "pasargad",
        "parsian",
        "saman",
        "resalat",
        "eghtesadnovin",
        "blubank",
        "wepod",
        "sadad",
        "asanpardakht",
        "behpardakht",
        "sepehr",
        "pec."
    )

    private val bankingLabelHints = listOf(
        "بانک",
        "همراه بانک",
        "موبایل بانک",
        "بانکداری",
        "بلوبانک",
        "بلو بانک",
        "ویپاد",
        "بام",
        "همراه کارت",
        "ایوا",
        "سکه",
        "۷۲۴"
    )

    private val exactDirectLabels = setOf(
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
            val pkg = info.packageName
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

            val exactDirect =
                exactPackages.contains(pkg) ||
                    exactDirectLabels.contains(label)
            val packageMatched =
                packageHints.any { lowerPackage.contains(it) }
            val bankingLabelMatched =
                bankingLabelHints.any { lowerLabel.contains(it) }

            if (exactDirect ||
                packageMatched ||
                bankingLabelMatched) {
                output += pkg
            }
        }

        return output.toList()
    }
}
