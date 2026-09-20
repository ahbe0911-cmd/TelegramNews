import 'package:shamsi_date/shamsi_date.dart';

String fa(Object value) => value
    .toString()
    .replaceAllMapped(RegExp(r'[0-9]'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)]);
String persianDate(DateTime date, {bool weekday = false}) {
  final f = Jalali.fromDateTime(date.toLocal()).formatter;
  return fa('${weekday ? '${f.wN} ' : ''}${f.d} ${f.mN} ${f.yyyy}');
}

class Post {
  final String id, title, text, html, url;
  final String? image;
  final DateTime date;
  final int? views;
  final bool important;
  const Post(
      {required this.id,
      required this.title,
      required this.text,
      required this.html,
      required this.url,
      required this.date,
      this.image,
      this.views,
      this.important = false});
  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: '${j['id']}',
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        html: j['html'] as String? ?? '',
        url: j['url'] as String? ?? '',
        image: j['image'] as String?,
        date: DateTime.fromMillisecondsSinceEpoch(
            (j['date'] as num).toInt() * 1000),
        views: (j['views'] as num?)?.toInt(),
        important: j['important'] == true,
      );
}

bool quietNow(DateTime now, bool enabled, int start, int end) {
  if (!enabled) return false;
  final minute = now.hour * 60 + now.minute;
  if (start == end) return true; // equal endpoints mean all day
  return start < end
      ? minute >= start && minute < end
      : minute >= start || minute < end;
}

final demoPosts = <Post>[
  Post(
      id: '3',
      title: 'خبرها، ساده‌تر و نزدیک‌تر',
      text:
          'این یک خبر نمونه برای پیش‌نمایش طراحی است. پس از اتصال کانال، پست‌های واقعی در این بخش نمایش داده می‌شوند.',
      html:
          '<p>این یک <b>خبر نمونه</b> است؛ محتوای زنده هنوز متصل نشده است.</p>',
      url: '',
      date: DateTime.now(),
      important: true),
  Post(
      id: '2',
      title: 'همه‌چیز در یک نگاه',
      text:
          'تاریخ شمسی، ساعت زنده، جست‌وجو و حالت شب؛ همراه شما در مرور خبرها.',
      html:
          '<p>خبرها را بخوانید، <i>به اشتراک بگذارید</i> و اعلان‌ها را مطابق سلیقه خود تنظیم کنید.</p>',
      url: '',
      date: DateTime.now().subtract(const Duration(hours: 2))),
  Post(
      id: '1',
      title: 'فضایی آرام برای خواندن',
      text: 'رابط فارسی و اندازه‌های خوانا، برای تمرکز روی آنچه اهمیت دارد.',
      html: '<p>این محتوا صرفاً نمایشی است.</p>',
      url: '',
      date: DateTime.now().subtract(const Duration(days: 1))),
];
