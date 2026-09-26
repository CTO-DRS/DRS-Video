# DRS Video

<div dir="rtl">

**درس فيديو** — مشغل فيديو متقدم و منصة مكتبة للأندرويد، مبني بـ Flutter و Material 3، بواجهة عربية أولاً (RTL).

## أحدث إصدار — v1.3.0

النوافذ العائمة + آلاف المواقع والمنصات:

- **نافذة فيديو عائمة داخل التطبيق** (مثل يوتيوب وتيك توك): عند الرجوع من المشغّل أو زر «تصغير»، يستمر الفيديو في نافذة صغيرة قابلة للسحب فوق أي شاشة — زر تشغيل/إيقاف، إغلاق، ونقر لفتح المشغّل الكامل (قابلة للتعطيل من الإعدادات).
- **PiP نظامي** (يدعم Android 8+، وتلقائي عند مغادرة التطبيق على Android 12+).
- **دعم آلاف المواقع والمنصات**:
  - **يوتيوب**: لصق أو مشاركة أي رابط يوتيوب (watch/youtu.be/shorts/live) ويعمل المشغّل بالبث الحقيقي حتى 1080p (فيديو + صوت منفصلان عبر mpv)، والبث المباشر عبر HLS.
  - **مشاركة من أي تطبيق**: زر «مشاركة ← DRS Video» من المتصفح أو يوتيوب أو أي تطبيق آخر يفتح الرابط مباشرة.
  - **فتح الروابط**: الروابط المرئية (video/*) وبروتوكولات rtsp/rtmp/rtmps/mms/ftp/sftp تفتح مع DRS Video من أي متصفح أو مدير ملفات.
  - **لصق سريع**: رقاقة «تشغيل الرابط من الحافظة» تظهر تلقائياً في تبويب المنصات.
- **محرّك الروابط الذكي**: كشف تلقائي للنوع (HLS/DASH/RTSP/RTMP/FTP/SFTP/ملف مباشر) وجلب عنوان الفيديو الحقيقي لروابط يوتيوب.
- استئناف المشاهدة يعمل حتى مع روابط يوتيوب (المعرّف ثابت للرابط، والبث يُحلّ من جديد في كل جلسة).

### الإصدارات السابقة

| الإصدار | أبرز الميزات |
|---------|--------------|
| v1.2.1 | إصلاح انهيار المشغل (Provider) + روابط مباشرة + IPTV + NAS (SFTP/FTP/WebDAV) |
| v1.1.0 | تحسينات المشغل والسمات والمجلدات والإحصاءات والنسخ الاحتياطي |
| v1.0.4 | إصلاح جذري لفشل الإقلاع (WorkManager مزدوج)، CrashGuard أصلي، تشخيصات كاملة |
| v1.0.3 | نظام تشخيص الأخطاء + دعم Android 7 (minSdk 24) |
| v1.0.2 | إقلاع آمن بدون أعمال native قبل أول إطار + سجل أعطال دائم |
| v1.0.1 | بوابة إقلاع مقاومة للفشل مع إعادة المحاولة والوضع الآمن |
| v1.0.0 | المشغل الكامل: إيماءات، PiP، مسارات، سرعة، مؤقت نوم، مكتبة، تنزيلات خلفية، قوائم تشغيل، بحث، توصيات |

### اختبار التحديث

- الترقية في المكان مدعومة (نفس مفتاح التوقيع: SHA-256 `72f9a501…`).
- **ملاحظة**: هذا الإصدار يدعم معمارية **arm64-v8a فقط** (كل الأجهزة الحديثة تقريباً) — قيود بيئة البناء؛ الأجهزة 32-بت القديمة جدًا غير مدعومة في هذا الإصدار.
- 105 اختبارات آلية جميعها ناجح؛ `flutter analyze` بدون أخطاء أو تحذيرات.
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
