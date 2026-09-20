/// Compile-time branding keeps the two applications independent without
/// duplicating their news, media, login or storage implementation.
class AppBrand {
  static const isCafenet = String.fromEnvironment('APP_VARIANT') == 'cafenet';
  static const title = isCafenet ? 'کافی‌نت' : 'نبض خبر';
  static const tagline = isCafenet ? 'اطلاعیه‌ها و خدمات کافی‌نت' : 'اخبار سریع، مطمئن، به‌روز';
  static const downloadFolder = isCafenet ? 'Cafenet' : 'NabzKhabar';
}
