package ir.channel.telegram_news

/** Android supports an allow-list OR a deny-list, never both. */
internal class VpnRoutingPolicy(
    val mode: String,
    selectedPackages: List<String>,
    selfPackage: String
) {
    val packages: List<String>

    init {
        require(mode == "all" || mode == "selected") { "Unknown routing mode" }
        require(selectedPackages.size <= 400) { "Too many selected apps" }
        val valid = Regex("^[A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z][A-Za-z0-9_]*)+$")
        packages = selectedPackages.distinct().filter { it != selfPackage }
        require(packages.all { valid.matches(it) }) { "Invalid package name" }
        require(mode != "selected" || packages.isNotEmpty()) {
            "Select another Android app or choose all apps"
        }
    }
}
