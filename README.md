# DRS Video

<div dir="rtl">

**درس فيديو** — مشغل فيديو متقدم و منصة مكتبة للأندرويد، مبني بـ Flutter و Material 3، بواجهة عربية أولاً (RTL).

## أحدث إصدار — v1.2.1

إصلاح حرج + منصات البث:

- **إصلاح عطل فادح**: فتح أي فيديو كان يسبب انهيار شاشة المشغل بسبب مزود (Provider) غير مسجّل — تم إصلاح السبب الجذري وتسجيل كل المزودات.
- **الروابط المباشرة**: أضف أي رابط فيديو/بث (HTTP، HTTPS، HLS، DASH، RTSP، RTMP، FTP) وشاهده داخل التطبيق.
- **IPTV**: استيراد قوائم M3U/M3U8 من رابط أو ملف، بحث SQL داخل القنوات، تصفية حسب المجموعات، شعارات القنوات، شارة «مباشر» مع تخطي استكمال التشغيل للبث الحي.
- **أجهزة الشبكة (NAS)**: WebDAV + FTP + SFTP — تصفح المجلدات وتشغيل الفيديو مباشرة (SFTP عبر وكيل بث محلي يدعم Range، FTP عبر بروتوكول mpv الأصلي، WebDAV مع Basic-Auth).
- **جودة البث**: تحديد سقف معدل البيت لقنوات HLS (تلقائي حتى 25 Mbps).
- **ترجمات خارجية**: من ملف محلي أو من رابط URL.
- استكمال التشغيل والمفضلة والسجل والإحصاءات تعمل مع كل المنصات تلقائياً (معرفات ثابتة للروابط والقنوات والملفات).
- ترقية قاعدة البيانات v2→v3 تلقائياً بدون فقدان البيانات.

### الإصدارات السابقة

| الإصدار | أبرز الميزات |
|---------|--------------|
| v1.0.4 | إصلاح جذري لفشل الإقلاع (WorkManager مزدوج)، CrashGuard أصلي، تشخيصات كاملة |
| v1.0.3 | نظام تشخيص الأخطاء + دعم Android 7 (minSdk 24) |
| v1.0.2 | إقلاع آمن بدون أعمال native قبل أول إطار + سجل أعطال دائم |
| v1.0.1 | بوابة إقلاع مقاومة للفشل مع إعادة المحاولة والوضع الآمن |
| v1.0.0 | المشغل الكامل: إيماءات، PiP، مسارات، سرعة، مؤقت نوم، مكتبة 7 تبويبات، تنزيلات خلفية، قوائم تشغيل، بحث، توصيات |

### اختبار التحديث

- الترقية في المكان مدعومة (نفس مفتاح التوقيع: SHA-256 `72f9a501…`).
- **ملاحظة**: هذا الإصدار يدعم معمارية **arm64-v8a فقط** (كل الأجهزة الحديثة تقريباً) — قيود بيئة البناء؛ الأجهزة 32-بت القديمة جدًا غير مدعومة في هذا الإصدار.
- 83 اختباراً آلياً جميعها ناجح؛ `flutter analyze` بدون أخطاء أو تحذيرات.
- عند أي مشكلة: الإعدادات ← التشخيص والأخطاء ← مشاركة التقرير.

</div>

## Getting Started

This project is a Flutter application.

```bash
flutter pub get
flutter test
flutter build apk --release
```

## Building for other platforms

The app targets Android here. The same codebase builds for other desktop /
mobile platforms from their native toolchains:

```bash
flutter config --enable-windows-desktop && flutter build windows
flutter config --enable-macos-desktop && flutter build macos
flutter config --enable-linux-desktop && flutter build linux
flutter build ios   # requires macOS + Xcode
```

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
