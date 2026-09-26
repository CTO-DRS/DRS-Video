# DRS Video

<div dir="rtl">

**درس فيديو** — مشغل فيديو متقدم و منصة مكتبة للأندرويد، مبني بـ Flutter و Material 3، بواجهة عربية أولاً (RTL).

## أحدث إصدار — v1.4.0

**متصفح المنصات المدمج + نظام الحماية + VPN مجاني:**

- **متصفح مدمج للمنصات** (مثل يوتيوب وتيك توك والمتصفح): تبويب «المواقع» يضم كتالوج 200+ منصة حقيقية مصنّفة (يوتيوب، تيك توك، شاهد، نتفليكس، إنستغرام، نتفليكس، أنگامي، ESPN، قنوات عربية...) + أضف أي موقع بنفسك + شريط عنوان مع بحث — كل ذلك **داخل التطبيق**.
- **تشغيل بأي طريقة**: اكتشاف الفيديو داخل الصفحة (HLS/DASH/MP4) وزر «تشغيل بالمشغل الأصلي»، وأي صفحة مشاهدة يوتيوب تُفتح بالمشغل الداخلي حتى 1080p، ثم يمكن تصغيرها إلى النافذة العائمة (v1.3.0).
- **حظر إعلانات ومتتبعات حقيقي**: قائمة مدمجة من **75,942 نطاق** (مشروع StevenBlack مفتوح المصدر) تُفحص على مستوى كل طلب شبكة داخل المتصفح + عدّاد مباشر للمحجوب + وضع تصفح خاص.
- **VPN مجاني بدون حساب**: عميل OpenVPN كامل مع قائمة **VPNGate** العامة (خوادم مجانية من جامعة تسوكوبا، تُحدّث لحظياً بالسرعة والبنق) + استيراد أي ملف `.ovpn` خاص بك — اتصال مشفر عبر إذن نظام VPN الرسمي.
- **بدون تجاوز DRM**: لا يتم فك حماية أي منصة — المنصات المدفوعة تعمل عبر مشغلاتها الرسمية داخل المتصفح.

### الإصدارات السابقة

| الإصدار | أبرز الميزات |
|---------|--------------|
| v1.3.0 | نافذة فيديو عائمة + تشغيل يوتيوب حقيقي + استقبال الروابط من أي تطبيق (مشاركة/فتح/حافظة) |
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
- 118 اختبارات آلية جميعها ناجح؛ `flutter analyze` بدون أخطاء أو تحذيرات.
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
