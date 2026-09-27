// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'DRS Video';

  @override
  String get ok => 'موافق';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get delete => 'حذف';

  @override
  String get edit => 'تعديل';

  @override
  String get add => 'إضافة';

  @override
  String get close => 'إغلاق';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get details => 'التفاصيل';

  @override
  String get share => 'مشاركة';

  @override
  String get rename => 'إعادة تسمية';

  @override
  String get copy => 'نسخ';

  @override
  String get copied => 'تم النسخ';

  @override
  String get open => 'فتح';

  @override
  String get play => 'تشغيل';

  @override
  String get pause => 'إيقاف مؤقت';

  @override
  String get resumeAction => 'استئناف';

  @override
  String get stop => 'إيقاف';

  @override
  String get done => 'تم';

  @override
  String get next => 'التالي';

  @override
  String get previous => 'السابق';

  @override
  String get continueWord => 'متابعة';

  @override
  String get search => 'بحث';

  @override
  String get filter => 'تصفية';

  @override
  String get sort => 'ترتيب';

  @override
  String get clear => 'مسح';

  @override
  String get loading => 'جارٍ التحميل…';

  @override
  String get error => 'خطأ';

  @override
  String get offline => 'غير متصل بالإنترنت';

  @override
  String get online => 'متصل';

  @override
  String get yes => 'نعم';

  @override
  String get no => 'لا';

  @override
  String get refresh => 'تحديث';

  @override
  String get selectAll => 'تحديد الكل';

  @override
  String get deselectAll => 'إلغاء التحديد';

  @override
  String itemsSelected(int count) {
    return '$count عنصر محدد';
  }

  @override
  String get deleteConfirmTitle => 'تأكيد الحذف';

  @override
  String deleteItemsMessage(int count) {
    return 'هل تريد حذف $count عنصرًا نهائيًا؟';
  }

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navLibrary => 'المكتبة';

  @override
  String get navPlaylists => 'القوائم';

  @override
  String get navDownloads => 'التنزيلات';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get homeSearchHint => 'ابحث في المكتبة والتنزيلات والملفات…';

  @override
  String get homeContinueWatching => 'متابعة المشاهدة';

  @override
  String get homeRecent => 'أُضيف حديثًا';

  @override
  String get homeFavorites => 'المفضلة';

  @override
  String get homeRecommended => 'مقترح لك';

  @override
  String get homeDownloads => 'التنزيلات';

  @override
  String get homePlaylists => 'قوائم التشغيل';

  @override
  String get homeSources => 'المصادر';

  @override
  String get homeLocalFiles => 'الملفات المحلية';

  @override
  String get homeQuickActions => 'إجراءات سريعة';

  @override
  String get homeOpenUrl => 'فتح رابط فيديو';

  @override
  String get homeOpenFile => 'فتح ملف فيديو';

  @override
  String get homeSeeAll => 'عرض الكل';

  @override
  String get emptyGenericTitle => 'لا يوجد شيء هنا بعد';

  @override
  String get emptyLibraryTitle => 'المكتبة فارغة';

  @override
  String get emptyLibraryBody => 'أضف رابطًا أو ملفًا محليًا لتبدأ.';

  @override
  String get emptyFavoritesTitle => 'لا مفضلات';

  @override
  String get emptyFavoritesBody => 'أضف فيديوهات إلى المفضلة لتجدها هنا.';

  @override
  String get emptyDownloadsTitle => 'لا تنزيلات';

  @override
  String get emptyDownloadsBody =>
      'افتح رابط فيديو واضغط زر التنزيل لبدء التنزيل.';

  @override
  String get emptyPlaylistsTitle => 'لا قوائم تشغيل';

  @override
  String get emptyPlaylistsBody => 'أنشئ قائمة تشغيل نظّم بها فيديوهاتك.';

  @override
  String get emptyHistoryTitle => 'لا سجل مشاهدة';

  @override
  String get emptyHistoryBody => 'ستظهر هنا الفيديوهات التي شاهدتها.';

  @override
  String get emptyLocalFilesTitle => 'لا ملفات محلية';

  @override
  String get emptyLocalFilesBody =>
      'لم نعثر على فيديوهات على الجهاز أو لم يُمنح الإذن بعد.';

  @override
  String get emptySearchTitle => 'لا نتائج';

  @override
  String get emptySearchBody => 'جرّب كلمات بحث أخرى أو عدّل التصفية.';

  @override
  String get emptyContinueTitle => 'لا مشاهدات غير مكتملة';

  @override
  String get emptyContinueBody =>
      'ابدأ بمشاهدة فيديو وستتمكن من متابعته من هنا.';

  @override
  String get actionPlayFromStart => 'تشغيل من البداية';

  @override
  String get actionAddToPlaylist => 'إضافة إلى قائمة تشغيل';

  @override
  String get actionRemoveFromPlaylist => 'إزالة من القائمة';

  @override
  String get actionFavorite => 'إضافة إلى المفضلة';

  @override
  String get actionUnfavorite => 'إزالة من المفضلة';

  @override
  String get actionShareLink => 'مشاركة الرابط';

  @override
  String get actionShareFile => 'مشاركة الملف';

  @override
  String get actionCopyLink => 'نسخ الرابط';

  @override
  String get actionOpenWith => 'فتح باستخدام';

  @override
  String get actionFileInfo => 'معلومات الملف';

  @override
  String get actionDownload => 'تنزيل';

  @override
  String get actionNewPlaylist => 'قائمة تشغيل جديدة';

  @override
  String get actionExport => 'تصدير';

  @override
  String get actionImport => 'استيراد';

  @override
  String get playerQuality => 'الجودة';

  @override
  String get playerSpeed => 'السرعة';

  @override
  String get playerAudioTrack => 'المسار الصوتي';

  @override
  String get playerSubtitleTrack => 'الترجمة';

  @override
  String get playerAddSubtitle => 'إضافة ملف ترجمة';

  @override
  String get playerSleepTimer => 'مؤقت النوم';

  @override
  String get playerOff => 'إيقاف';

  @override
  String get playerEndOfVideo => 'نهاية الفيديو';

  @override
  String playerMinutes(int count) {
    return '$count دقيقة';
  }

  @override
  String get playerPiP => 'نافذة عائمة (PiP)';

  @override
  String get playerLock => 'قفل التحكم';

  @override
  String get playerUnlock => 'فتح التحكم';

  @override
  String get playerFullscreen => 'ملء الشاشة';

  @override
  String get playerAuto => 'تلقائي';

  @override
  String get playerSingleQuality => 'يوفر المصدر جودة واحدة فقط';

  @override
  String get playerNoAudioTracks => 'لا توجد مسارات صوتية إضافية';

  @override
  String get playerNoSubtitleTracks => 'لا توجد ترجمات — يمكنك إضافة ملف ترجمة';

  @override
  String get playerExternalSubtitle => 'ملف خارجي';

  @override
  String get playerSubLoaded => 'تم تحميل ملف الترجمة';

  @override
  String get playerSubInvalid => 'ملف الترجمة غير صالح أو فارغ';

  @override
  String get playerBuffering => 'جارٍ التخزين المؤقت…';

  @override
  String get playerErrorTitle => 'تعذر تشغيل الفيديو';

  @override
  String get playerErrorNetwork =>
      'تعذر الوصول إلى الرابط. تحقق من اتصالك بالإنترنت وصحة الرابط.';

  @override
  String get playerErrorTimeout => 'استغرق المصدر وقتًا طويلًا للاستجابة.';

  @override
  String get playerErrorUnsupported =>
      'صيغة الفيديو غير مدعومة على هذا الجهاز.';

  @override
  String get playerErrorCorrupted => 'الملف تالف أو غير مكتمل.';

  @override
  String get playerErrorNotFound => 'الملف أو الرابط غير موجود (404).';

  @override
  String get playerErrorForbidden => 'المصدر يمنع التشغيل من خارج موقعه.';

  @override
  String get playerErrorUnknown => 'حدث خطأ غير متوقع أثناء التشغيل.';

  @override
  String get openInBrowser => 'افتح في المتصفح المدمج';

  @override
  String get openExternal => 'افتح في متصفح خارجي';

  @override
  String get openExternalUnavailable => 'لا يوجد متصفح خارجي مثبت على الجهاز';

  @override
  String get browserLoadFailed =>
      'تعذر تحميل الصفحة. تحقق من الاتصال أو جرّب متصفحاً خارجياً.';

  @override
  String playerResumeFrom(String time) {
    return 'متابعة من $time؟';
  }

  @override
  String get playerStartOver => 'من البداية';

  @override
  String get playerBrightness => 'السطوع';

  @override
  String get playerVolume => 'الصوت';

  @override
  String get playerFrameStepHint => 'خطوة إطار';

  @override
  String get playerSkipIntro => 'تخطي المقدمة';

  @override
  String get playerSkipOutro => 'تخطي الخاتمة';

  @override
  String get playerNextVideo => 'الفيديو التالي';

  @override
  String get playerPrevVideo => 'الفيديو السابق';

  @override
  String get playerCompleted => 'اكتمل التشغيل';

  @override
  String get downloadsActive => 'قيد التنزيل';

  @override
  String get downloadsQueued => 'في الانتظار';

  @override
  String get downloadsCompleted => 'مكتملة';

  @override
  String get downloadsFailed => 'فاشلة';

  @override
  String get downloadsPauseAll => 'إيقاف الكل مؤقتًا';

  @override
  String get downloadsResumeAll => 'استئناف الكل';

  @override
  String get downloadsPriority => 'الأولوية';

  @override
  String get downloadsPriorityHigh => 'عالية';

  @override
  String get downloadsPriorityNormal => 'عادية';

  @override
  String get downloadsPriorityLow => 'منخفضة';

  @override
  String downloadsFreeSpace(String size) {
    return 'المساحة المتاحة: $size';
  }

  @override
  String get downloadsCorruptedFile =>
      'يبدو أن الملف غير مكتمل — أعد المحاولة للإصلاح.';

  @override
  String get downloadStarted => 'بدأ التنزيل';

  @override
  String get downloadCompletedNotif => 'اكتمل التنزيل';

  @override
  String get downloadFailedNotif => 'فشل التنزيل';

  @override
  String get downloadsWifiOnlyWarning =>
      'التنزيل عبر Wi-Fi فقط مُفعّل — انتظر اتصال Wi-Fi.';

  @override
  String get downloadsInsufficientSpace => 'لا توجد مساحة تخزين كافية.';

  @override
  String get downloadsServerNoResume =>
      'الخادم لا يدعم استكمال التنزيل؛ سيبدأ من جديد عند الاستئناف.';

  @override
  String get libraryAll => 'الكل';

  @override
  String get libraryFavorites => 'المفضلة';

  @override
  String get libraryDownloads => 'التنزيلات';

  @override
  String get libraryRecent => 'الأحدث';

  @override
  String get libraryContinue => 'المتابعة';

  @override
  String get libraryLocal => 'المحلية';

  @override
  String get libraryHistory => 'السجل';

  @override
  String get librarySortBy => 'الترتيب حسب';

  @override
  String get sortName => 'الاسم';

  @override
  String get sortDateAdded => 'تاريخ الإضافة';

  @override
  String get sortRecentlyPlayed => 'آخر مشاهدة';

  @override
  String get sortDuration => 'المدة';

  @override
  String get sortSize => 'الحجم';

  @override
  String get filterType => 'النوع';

  @override
  String get filterSource => 'المصدر';

  @override
  String get filterDuration => 'المدة';

  @override
  String get filterFavoritesOnly => 'المفضلة فقط';

  @override
  String get durationShort => 'أقل من 5 دقائق';

  @override
  String get durationMedium => '5 – 20 دقيقة';

  @override
  String get durationLong => '20 – 60 دقيقة';

  @override
  String get durationVeryLong => 'أكثر من ساعة';

  @override
  String get typeAll => 'الكل';

  @override
  String get typeLocal => 'ملف محلي';

  @override
  String get typeNetwork => 'رابط';

  @override
  String get typeDownload => 'تنزيل';

  @override
  String get multiSelectTitle => 'تحديد متعدد';

  @override
  String playlistsCount(int count) {
    return '$count فيديو';
  }

  @override
  String get playlistNameHint => 'اسم القائمة';

  @override
  String get playlistPlayAll => 'تشغيل القائمة';

  @override
  String get playlistShuffle => 'تشغيل عشوائي';

  @override
  String get playlistRepeat => 'التكرار';

  @override
  String get repeatOff => 'بدون تكرار';

  @override
  String get repeatAll => 'تكرار القائمة';

  @override
  String get repeatOne => 'تكرار الحالي';

  @override
  String get playlistReorderHint => 'اسحب لإعادة الترتيب';

  @override
  String get playlistExported => 'تم تصدير القائمة للمشاركة';

  @override
  String get playlistImported => 'تم استيراد القائمة';

  @override
  String get playlistInvalidFile => 'ملف القائمة غير صالح';

  @override
  String get playlistPickVideos => 'اختر فيديوهات للإضافة';

  @override
  String get searchHint => 'ابحث بالعنوان أو المصدر…';

  @override
  String get searchSuggestions => 'اقتراحات';

  @override
  String get searchRecentQueries => 'أبحاث سابقة';

  @override
  String get searchResults => 'النتائج';

  @override
  String get searchClearHistory => 'مسح سجل البحث';

  @override
  String get sourcesTitle => 'المصادر';

  @override
  String get sourcesLocalAdapter => 'الملفات المحلية';

  @override
  String get sourcesLocalAdapterDesc => 'فيديوهات الجهاز عبر MediaStore';

  @override
  String get sourcesDirectAdapter => 'روابط مباشرة';

  @override
  String get sourcesDirectAdapterDesc =>
      'ملفات MP4 / MKV / WebM وروابط HLS المباشرة';

  @override
  String get sourcesAddTitle => 'إضافة مصدر';

  @override
  String get sourcesNameHint => 'اسم المصدر';

  @override
  String get sourcesBaseUrlHint => 'عنوان المصدر الأساسي (https://…)';

  @override
  String get sourcesHeaderHint =>
      'ترويسة اختيارية (مثل Authorization: Bearer …)';

  @override
  String get sourcesTest => 'اختبار الاتصال';

  @override
  String get sourcesTestOk => 'الاتصال ناجح';

  @override
  String get sourcesTestFail => 'فشل الاتصال';

  @override
  String get sourcesEnabled => 'مفعّل';

  @override
  String get sourcesDisabled => 'معطّل';

  @override
  String get sourcesDeleteWarn =>
      'سيُحذف المصدر فقط، ولن تُحذف الفيديوهات المحفوظة.';

  @override
  String get sourcesPrivacyNote =>
      'لا يدعم التطبيق تجاوز حماية أي منصة؛ يعمل فقط مع المصادر التي تسمح رسميًا بالوصول المباشر.';

  @override
  String get localFilesPermissionNeeded =>
      'إذن الوصول إلى الوسائط مطلوب لعرض فيديوهات الجهاز.';

  @override
  String get localFilesGrant => 'منح الإذن';

  @override
  String get localFilesScanning => 'جارٍ فحص الوسائط…';

  @override
  String get fileInfoTitle => 'معلومات الملف';

  @override
  String get fileInfoPath => 'المسار';

  @override
  String get fileInfoSize => 'الحجم';

  @override
  String get fileInfoDuration => 'المدة';

  @override
  String get fileInfoAdded => 'أُضيف في';

  @override
  String get fileInfoLastPlayed => 'آخر مشاهدة';

  @override
  String get fileInfoTimesPlayed => 'مرات التشغيل';

  @override
  String get settingsPlayback => 'التشغيل';

  @override
  String get settingsDownloads => 'التنزيلات';

  @override
  String get settingsAppearance => 'المظهر';

  @override
  String get settingsStorage => 'التخزين';

  @override
  String get settingsPrivacy => 'الخصوصية';

  @override
  String get settingsNotifications => 'الإشعارات';

  @override
  String get settingsAbout => 'حول التطبيق';

  @override
  String get setDefaultQuality => 'الجودة الافتراضية';

  @override
  String get qualityAuto => 'تلقائي حسب الاتصال';

  @override
  String get qualityHigh => 'أعلى جودة';

  @override
  String get qualityMedium => 'متوسطة';

  @override
  String get qualityLow => 'موفر للبيانات';

  @override
  String get setDefaultSpeed => 'سرعة التشغيل الافتراضية';

  @override
  String get setAutoPlayNext => 'تشغيل التالي تلقائيًا';

  @override
  String get setAutoPlayNextDesc =>
      'بدء الفيديو التالي في قائمة الانتظار عند الانتهاء';

  @override
  String get setAlwaysResume => 'استكمال المشاهدة دائمًا';

  @override
  String get setAlwaysResumeDesc => 'الاستئناف من آخر موضع دون سؤال';

  @override
  String get setPip => 'نافذة عائمة PiP';

  @override
  String get setPipDesc => 'مشاهدة الفيديو في نافذة صغيرة أثناء التنقل';

  @override
  String get setAutoPip => 'PiP تلقائي عند الخروج';

  @override
  String get setAutoPipDesc =>
      'التحول إلى النافذة العائمة عند مغادرة التطبيق (أندرويد 12+)';

  @override
  String get setFloatingPlayer => 'نافذة فيديو عائمة داخل التطبيق';

  @override
  String get setFloatingPlayerDesc =>
      'عند الرجوع من المشغّل يستمر الفيديو في نافذة صغيرة قابلة للسحب (مثل يوتيوب وتيك توك)';

  @override
  String get playerFloat => 'تصغير إلى نافذة عائمة';

  @override
  String get shareOpenTitle => 'فتح رابط الفيديو؟';

  @override
  String get shareOpenBody => 'تم مشاركة الرابط التالي مع DRS Video:';

  @override
  String get sharePlayNow => 'تشغيل الآن';

  @override
  String get shareSaveOnly => 'حفظ فقط';

  @override
  String get clipboardPaste => 'تشغيل الرابط من الحافظة';

  @override
  String get platformsSupportedHint =>
      'يدعم: روابط مباشرة (mp4/mkv/...)، HLS و DASH، RTSP/RTMP، FTP/SFTP، WebDAV، يوتيوب — وآلاف المواقع عبر المشاركة من أي تطبيق';

  @override
  String get setBackground => 'تشغيل في الخلفية';

  @override
  String get setBackgroundDesc =>
      'استمرار الصوت مع إشعار وسائط عند تصغير التطبيق';

  @override
  String get setPreferFullscreen => 'البدء بملء الشاشة';

  @override
  String get setDownloadFolder => 'مجلد التنزيل';

  @override
  String get setDownloadFolderDesc =>
      'افتراضيًا يُحفظ داخل مجلد التطبيق الخاص دون أذونات';

  @override
  String get setUseCustomFolder => 'اختيار مجلد مخصص';

  @override
  String get setCustomFolderNeedsAllFiles =>
      'يتطلب المجلد المخصص إذن \"كل الملفات\" لأندرويد 11+';

  @override
  String get setConcurrency => 'التنزيلات المتزامنة';

  @override
  String get setWifiOnly => 'التنزيل عبر Wi-Fi فقط';

  @override
  String get setNotifyDone => 'إشعار اكتمال التنزيل';

  @override
  String get setNotifyError => 'إشعار أخطاء التنزيل';

  @override
  String get setNotifyStorage => 'تحذير المساحة';

  @override
  String get setThemeMode => 'الوضع';

  @override
  String get themeSystem => 'النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get setDynamicColor => 'الألوان الديناميكية';

  @override
  String get setDynamicColorDesc =>
      'استخراج ألوان النظام (Material You) على أندرويد 12+';

  @override
  String get setAnimations => 'الحركات';

  @override
  String get setLayout => 'كثافة الواجهة';

  @override
  String get layoutCompact => 'مدمجة';

  @override
  String get layoutComfortable => 'مريحة';

  @override
  String get setLanguage => 'اللغة';

  @override
  String get langSystem => 'لغة النظام';

  @override
  String get langArabic => 'العربية';

  @override
  String get langEnglish => 'English';

  @override
  String get storageThumbnails => 'ذاكرة الصور المصغرة';

  @override
  String get storageDownloadsSize => 'حجم التنزيلات';

  @override
  String get storageClearCache => 'مسح ذاكرة التخزين المؤقت';

  @override
  String get storageCleared => 'تم المسح';

  @override
  String get storageAnalyzer => 'محلل التخزين';

  @override
  String get storageLargestFiles => 'أكبر الملفات';

  @override
  String get storageOldestUnplayed => 'أقدم الملفات غير المشاهدة';

  @override
  String get privacyHistoryEnabled => 'تفعيل سجل المشاهدة';

  @override
  String get privacyHistoryDesc => 'يُحفظ محليًا فقط ولا يُرسل لأي خادم';

  @override
  String get privacyClearHistory => 'مسح سجل المشاهدة';

  @override
  String get privacyClearSearch => 'مسح سجل البحث';

  @override
  String get privacyClearAllData => 'مسح جميع البيانات المحلية';

  @override
  String get privacyClearAllConfirm =>
      'سيُحذف السجل والمفضلات وقوائم التشغيل وإعدادات التنزيل. هل أنت متأكد؟';

  @override
  String get privacyLocalDataNote =>
      'جميع البيانات (السجل، المفضلة، القوائم) محفوظة على جهازك فقط.';

  @override
  String get privacyPermissions => 'الأذونات';

  @override
  String get privacyExportLogs => 'تصدير سجلات التشخيص';

  @override
  String get notifChannelDownloads => 'التنزيلات';

  @override
  String get notifChannelGeneral => 'عام';

  @override
  String get aboutVersion => 'الإصدار';

  @override
  String get aboutLicenses => 'تراخيص المصادر المفتوحة';

  @override
  String get aboutPrivacyPolicy => 'سياسة الخصوصية';

  @override
  String get aboutPrivacyBody =>
      'لا يجمع DRS Video أي بيانات شخصية ولا يرسل سجل المشاهدة إلى أي خادم. كل شيء يبقى على جهازك. الاتصال بالإنترنت يقتصر على تشغيل وتنزيل المحتوى الذي تختاره أنت.';

  @override
  String get aboutDescription =>
      'مشغل فيديو ومنصة مكتبة متقدمة — بدون إعلانات وبدون ذكاء اصطناعي.';

  @override
  String get permNotificationTitle => 'إذن الإشعارات';

  @override
  String get permNotificationDesc => 'لإظهار تقدم التنزيلات واكتمالها.';

  @override
  String get permMediaTitle => 'إذن الوسائط';

  @override
  String get permMediaDesc => 'لعرض ملفات الفيديو الموجودة على جهازك.';

  @override
  String get permAllFilesTitle => 'إذن كل الملفات';

  @override
  String get permAllFilesDesc => 'مطلوب فقط لحفظ التنزيلات في مجلد مخصص.';

  @override
  String get permOpenSettings => 'فتح إعدادات النظام';

  @override
  String get ob1Title => 'كل فيديوهاتك في مكان واحد';

  @override
  String get ob1Body =>
      'المكتبة والمفضلة وقوائم التشغيل وسجل المشاهدة — منظمة محليًا على جهازك.';

  @override
  String get ob2Title => 'مشغل احترافي';

  @override
  String get ob2Body =>
      'سرعات، ترجمات، مسارات صوتية، قفل، نافذة عائمة، وتحكم بالإيماءات.';

  @override
  String get ob3Title => 'تنزيل حقيقي في الخلفية';

  @override
  String get ob3Body =>
      'إيقاف مؤقت واستئناف وإدارة أولويات — من المصادر التي تسمح بذلك.';

  @override
  String get obGetStarted => 'لنبدأ';

  @override
  String get obSkip => 'تخطي';

  @override
  String get openUrlTitle => 'فتح رابط فيديو';

  @override
  String get openUrlHint => 'https://example.com/video.mp4';

  @override
  String get openUrlInvalid => 'رابط غير صالح — يجب أن يبدأ بـ http/https';

  @override
  String get pickSubtitle => 'اختر ملف ترجمة (SRT / VTT)';

  @override
  String get renameTitle => 'إعادة تسمية';

  @override
  String get reasonFavorite => 'من مفضلاتك';

  @override
  String get reasonRecentlyPlayed => 'شاهدته مؤخرًا';

  @override
  String get reasonUnfinished => 'لم تكمله';

  @override
  String reasonFromSource(String source) {
    return 'من $source';
  }

  @override
  String get reasonSimilarSource => 'مصادر تحبها';

  @override
  String get updateThumb => 'تحديث';

  @override
  String get scanComplete => 'اكتمل الفحص';

  @override
  String get waiting => 'بالانتظار…';

  @override
  String get bootPreparing => 'جارٍ تجهيز التطبيق…';

  @override
  String get bootStageCore => 'تحضير الأساسيات';

  @override
  String get bootStagePrefs => 'تحميل الإعدادات';

  @override
  String get bootStageDatabase => 'تهيئة قاعدة البيانات';

  @override
  String get bootStageRepositories => 'تحميل المكتبة والسجل';

  @override
  String get bootStageNotifications => 'تهيئة الإشعارات';

  @override
  String get bootStagePlayer => 'تجهيز محرك التشغيل';

  @override
  String get bootStageDownloads => 'تجهيز مدير التحميلات';

  @override
  String get bootStageSources => 'تحميل المصادر';

  @override
  String get bootSlow =>
      'التجهيز يستغرق وقتًا أطول من المعتاد. يمكنك إعادة المحاولة أو المتابعة بالانتظار.';

  @override
  String get bootRetry => 'إعادة المحاولة';

  @override
  String get bootSafeMode => 'الوضع الآمن';

  @override
  String get bootErrorTitle => 'تعذّر تشغيل التطبيق';

  @override
  String get bootErrorBody =>
      'حدث خطأ أثناء تهيئة التطبيق. أعد المحاولة، أو ابدأ بالوضع الآمن الذي يبدأ التطبيق بأقل قدر من الميزات.';

  @override
  String get bootErrorDetails => 'التفاصيل التقنية';

  @override
  String get bootErrorCopy => 'نسخ التفاصيل';

  @override
  String get bootErrorCopied => 'تم نسخ التفاصيل إلى الحافظة';

  @override
  String get bootPrevCrashTitle => 'تم رصد مشكلة في الجلسة السابقة';

  @override
  String get bootPrevCrashBody =>
      'لم يُغلق التطبيق بشكل سليم في المرة الأخيرة. يمكنك نسخ التفاصيل أدناه وإرسالها إلينا لمعرفة السبب.';

  @override
  String get bootPrevCrashDetails => 'تفاصيل العطل';

  @override
  String get setDiagnostics => 'التشخيص والأخطاء';

  @override
  String get diagDeviceSection => 'معلومات الجهاز';

  @override
  String get diagFactsApp => 'التطبيق';

  @override
  String get diagFactsDevice => 'الجهاز';

  @override
  String get diagFactsAndroid => 'أندرويد';

  @override
  String get diagFactsAbi => 'المعمارية';

  @override
  String get diagFactsStorage => 'مساحة التخزين';

  @override
  String get diagChecksSection => 'فحوصات الخدمات';

  @override
  String get diagRunChecks => 'فحص الآن';

  @override
  String get diagStatusPass => 'سليم';

  @override
  String get diagStatusDegraded => 'محدود';

  @override
  String get diagStatusFail => 'فاشل';

  @override
  String get diagCheckPrefs => 'التفضيلات المحفوظة';

  @override
  String get diagCheckDatabase => 'قاعدة البيانات';

  @override
  String get diagCheckStorage => 'التخزين الداخلي';

  @override
  String get diagCheckPlayer => 'محرك التشغيل (mpv)';

  @override
  String get diagCheckDownloader => 'محرك التحميلات';

  @override
  String get diagCheckNotifications => 'الإشعارات';

  @override
  String get diagCheckNative => 'جسر النظام (Native)';

  @override
  String get diagCheckCache => 'الذاكرة المؤقتة';

  @override
  String get diagCheckCrashes => 'سجل الأعطال';

  @override
  String get diagCrashesSection => 'الأعطال المُسجلة';

  @override
  String get diagNoCrashes => 'لا توجد أعطال مُسجلة من الجلسات السابقة.';

  @override
  String get diagPrevCrashDetails => 'عرض تفاصيل العطل';

  @override
  String get diagClearLogs => 'مسح السجلات';

  @override
  String get diagLogsCleared => 'تم مسح سجلات الأعطال';

  @override
  String get diagSessionLog => 'سجل الجلسة الحالية';

  @override
  String get diagSessionLogBody => 'آخر 120 حدثًا مسجلاً خلال هذه الجلسة';

  @override
  String get diagCopyReport => 'نسخ';

  @override
  String get diagReportCopied => 'تم النسخ إلى الحافظة';

  @override
  String get diagShareReport => 'مشاركة التقرير الكامل';

  @override
  String get diagLocalNote =>
      'كل شيء يبقى على جهازك ولا يُرسل أي بيان إلا إذا شاركت التقرير بنفسك.';

  @override
  String get dlDegradedTitle => 'محرك التحميلات غير متاح حاليًا';

  @override
  String get dlDegradedRetry => 'إعادة تهيئة محرك التحميلات';

  @override
  String get bootSafeModePreparing => 'جارٍ التشغيل بالوضع الآمن…';

  @override
  String get libraryPlatforms => 'المنصات';

  @override
  String get platformsLinks => 'الروابط';

  @override
  String get platformsIptv => 'قوائم IPTV';

  @override
  String get platformsNas => 'أجهزة الشبكة';

  @override
  String get addLinkTitle => 'إضافة رابط';

  @override
  String get addLinkUrlHint => 'رابط الفيديو أو البث';

  @override
  String get addLinkNameHint => 'الاسم (اختياري)';

  @override
  String get addLinkPlayNow => 'تشغيل الآن';

  @override
  String get addLinkSaveOnly => 'حفظ فقط';

  @override
  String get addLinkInvalid => 'رابط غير مدعوم أو غير صالح';

  @override
  String get linkSaved => 'تم حفظ الرابط';

  @override
  String get copyLink => 'نسخ الرابط';

  @override
  String get linkCopied => 'تم نسخ الرابط';

  @override
  String resumeFrom(String time) {
    return 'استكمال من $time';
  }

  @override
  String get platformsEmptyLinks => 'لا روابط محفوظة بعد';

  @override
  String get platformsEmptyLinksBody =>
      'أضف رابط فيديو أو بث مباشر (HTTP، HLS، DASH، RTSP، RTMP، FTP) لتشغيله من هنا';

  @override
  String get platformsEmptyIptv => 'لا قوائم IPTV بعد';

  @override
  String get platformsEmptyIptvBody =>
      'استورد قائمة M3U/M3U8 من رابط أو من ملف، وشاهد القنوات داخل التطبيق';

  @override
  String get platformsEmptyNas => 'لا أجهزة شبكة بعد';

  @override
  String get platformsEmptyNasBody =>
      'أضف خادم WebDAV أو FTP أو SFTP لتصفح ملفاته وتشغيل مقاطع الفيديو منه';

  @override
  String get iptvImport => 'استيراد قائمة';

  @override
  String get iptvImportUrl => 'استيراد من رابط';

  @override
  String get iptvImportFile => 'استيراد من ملف';

  @override
  String get iptvImportNameHint => 'اسم القائمة (اختياري)';

  @override
  String get iptvImportUrlHint => 'رابط قائمة M3U/M3U8';

  @override
  String get iptvImporting => 'جارٍ استيراد القائمة…';

  @override
  String iptvImportDone(int count) {
    return 'تم استيراد $count قناة';
  }

  @override
  String iptvImportFail(String error) {
    return 'فشل الاستيراد: $error';
  }

  @override
  String iptvChannels(int count) {
    return '$count قناة';
  }

  @override
  String get iptvGroupsAll => 'كل المجموعات';

  @override
  String get iptvSearchChannels => 'ابحث في القنوات';

  @override
  String get iptvDeleteConfirmTitle => 'حذف القائمة؟';

  @override
  String iptvDeleteConfirmBody(String name) {
    return 'سيتم حذف قائمة “$name” وقنواتها من التطبيق';
  }

  @override
  String get iptvLoadFail => 'تعذر تحميل القنوات';

  @override
  String get iptvNoChannels => 'لا قنوات مطابقة';

  @override
  String get nasAddServer => 'إضافة خادم شبكة';

  @override
  String get nasName => 'الاسم';

  @override
  String get nasHost => 'العنوان (IP أو اسم المضيف)';

  @override
  String get nasPort => 'المنفذ';

  @override
  String get nasUsername => 'اسم المستخدم (اختياري)';

  @override
  String get nasPassword => 'كلمة المرور (اختياري)';

  @override
  String get nasUseTls => 'اتصال آمن (HTTPS)';

  @override
  String nasConnectFail(String error) {
    return 'فشل الاتصال: $error';
  }

  @override
  String get nasDeleteConfirmTitle => 'حذف الخادم؟';

  @override
  String nasDeleteConfirmBody(String name) {
    return 'سيتم نسيان “$name”؛ يمكنك إضافته مجدداً لاحقاً';
  }

  @override
  String nasBrowseFail(String error) {
    return 'فشل التصفح: $error';
  }

  @override
  String get nasEmptyFolder => 'المجلد فارغ';

  @override
  String get nasUp => 'إلى المجلد الأعلى';

  @override
  String get nasRoot => 'الجذر';

  @override
  String get liveBadge => 'مباشر';

  @override
  String qualityCap(int kbps) {
    return 'حتى $kbps kbps';
  }

  @override
  String get playerVideoTrack => 'مسار الفيديو';

  @override
  String get addSubtitleUrl => 'إضافة رابط ترجمة';

  @override
  String get subtitleUrlHint => 'رابط ملف الترجمة (SRT/VTT)';

  @override
  String get subtitleAdded => 'تم تحميل الترجمة';

  @override
  String get subtitleInvalid => 'تعذر تحميل الترجمة';

  @override
  String get platformsSites => 'المواقع';

  @override
  String get sitesSearchHint => 'ابحث عن منصة (YouTube، TikTok، شاهد...)';

  @override
  String get sitesAll => 'الكل';

  @override
  String get sitesCatMine => 'مواقعي';

  @override
  String get sitesCatVideo => 'فيديو';

  @override
  String get sitesCatArabic => 'عربية';

  @override
  String get sitesCatMovies => 'أفلام';

  @override
  String get sitesCatLive => 'أخبار وبث';

  @override
  String get sitesCatSports => 'رياضة';

  @override
  String get sitesCatMusic => 'موسيقى';

  @override
  String get sitesCatAnime => 'أنمي';

  @override
  String get sitesCatSocial => 'تواصل';

  @override
  String get sitesCatLearn => 'تعليم';

  @override
  String get sitesCatTv => 'تلفزيون';

  @override
  String get sitesAddAny => 'أضف أي موقع';

  @override
  String get sitesAddTitle => 'إضافة موقع';

  @override
  String get sitesAddName => 'الاسم';

  @override
  String get sitesAddUrl => 'العنوان';

  @override
  String get sitesNameRequired => 'الاسم مطلوب';

  @override
  String get sitesBookmarks => 'العلامات المرجعية';

  @override
  String get bookmarksEmpty =>
      'لا توجد علامات مرجعية بعد — استخدم نجمة داخل المتصفح لحفظ الصفحات';

  @override
  String get bookmarkAdded => 'أضيف إلى العلامات المرجعية';

  @override
  String get bookmarkRemoved => 'أزيل من العلامات المرجعية';

  @override
  String get bookmarkAdd => 'حفظ في العلامات المرجعية';

  @override
  String get bookmarkRemove => 'إزالة من العلامات المرجعية';

  @override
  String get browserUaTooltip => 'التبديل بين واجهة الجوال وواجهة سطح المكتب';

  @override
  String browserBlockedSession(int count) {
    return 'المحجوبة في هذه الصفحة: $count';
  }

  @override
  String get browserAddressHint => 'ابحث أو أدخل عنوان موقع';

  @override
  String get browserShieldTooltip => 'الحماية وحظر الإعلانات';

  @override
  String get browserStreamsTooltip => 'الفيديوهات المكتشفة في الصفحة';

  @override
  String get browserStreamsTitle => 'فيديو مكتشف في الصفحة';

  @override
  String get browserPlayThisPage => 'تشغيل هذه الصفحة بمشغل DRS';

  @override
  String get browserPlayInPlayer => 'تشغيل بالمشغل الأصلي';

  @override
  String get browserNoStreams =>
      'لم يُكتشف فيديو قابل للتشغيل في هذه الصفحة بعد — تنقل داخل الموقع وحاول مجدداً';

  @override
  String get browserPlayFailed => 'تعذر فتح هذا الرابط في المشغل';

  @override
  String get protectionTitle => 'الحماية والـ VPN';

  @override
  String get protectionAdBlockTitle => 'الحماية من الإعلانات';

  @override
  String get protectionAdBlock => 'حظر الإعلانات والمتتبعات';

  @override
  String get protectionAdBlockDesc =>
      'يحجب أكثر من 75 ألف نطاق إعلانات ومتتبعات داخل المتصفح المدمج';

  @override
  String get protectionIncognito => 'التصفح الخاص';

  @override
  String get protectionIncognitoDesc => 'عدم حفظ سجل التصفح';

  @override
  String protectionBlockedTotal(int count) {
    return 'الطلبات المحجوبة حتى الآن: $count';
  }

  @override
  String get protectionResetCounter => 'تصفير';

  @override
  String get protectionBlocklistInfo =>
      'قائمة الحظر من مشروع StevenBlack مفتوح المصدر (رخصة MIT) وتُحدّث مع كل إصدار. لا يتم تجاوز أنظمة حماية المحتوى (DRM) لأي منصة.';

  @override
  String get browserYtAdKillTitle => 'حماية يوتيوب من الإعلانات';

  @override
  String get browserYtAdKillSub =>
      'تخطي تلقائي للإعلانات وإخفاؤها داخل المشغّل وصفحات البحث والرئيسية';

  @override
  String get ghTitle => 'جيثب والتحديثات';

  @override
  String get ghUpdateSection => 'تحديث التطبيق';

  @override
  String ghCurrentVersion(String v) {
    return 'الإصدار الحالي: $v';
  }

  @override
  String ghUpdateAvailable(String tag) {
    return 'يتوفر تحديث جديد: $tag';
  }

  @override
  String get ghCheckUpdate => 'فحص الآن';

  @override
  String get ghDownloading => 'جارٍ التحميل…';

  @override
  String ghDownloadingPct(int p) {
    return 'جارٍ التحميل… $p%';
  }

  @override
  String get ghInstalling => 'تم التحميل — جارٍ فتح المثبّت…';

  @override
  String get ghInstall => 'تثبيت التحديث';

  @override
  String get ghInstallFailed =>
      'تعذر بدء التثبيت (تحقق من إذن تثبيت التطبيقات)';

  @override
  String get ghAutoCheck => 'فحص التحديثات تلقائيًا';

  @override
  String get ghAutoCheckDesc => 'عند تشغيل التطبيق يُفحص جيثب بصمت';

  @override
  String get ghReleasesSection => 'الإصدارات السابقة';

  @override
  String get ghNoReleases => 'لا توجد إصدارات — تحقق من الاتصال';

  @override
  String get ghNoNotes => 'لا توجد ملاحظات إصدار';

  @override
  String get ghOpenRepo => 'مستودع المشروع';

  @override
  String get ghOpenReleases => 'صفحة الإصدارات';

  @override
  String get ghOpenDeveloper => 'حساب المطوّر';

  @override
  String get ghOpen => 'فتح';

  @override
  String get playerBookmarks => 'العلامات المرجعية';

  @override
  String get playerBookmarkEmpty =>
      'لا علامات بعد — أضف علامة عند اللحظة الحالية';

  @override
  String get playerBookmarkAdd => 'علامة هنا';

  @override
  String get playerCapture => 'التقاط صورة من الفيديو';

  @override
  String get playerCaptureOk => 'تم حفظ الصورة في مجلد صور التطبيق';

  @override
  String get playerCaptureFail => 'تعذر التقاط الصورة';

  @override
  String get playerIntroEnd => 'نهاية المقدمة هنا';

  @override
  String playerIntroEndSet(int s) {
    return 'سيبدأ المقطع القادم في هذا المجلد من الثانية $s';
  }

  @override
  String get protectionHonestNote =>
      'ملاحظة صادقة: حظر الإعلانات يعمل داخل المتصفح المدمج. بعض المنصات (مثل يوتيوب) تُدمج إعلاناتها مع محتوى الفيديو نفسه فلا يمكن حجبها دون تعطيل التشغيل. يعمل VPN عبر OpenVPN فقط على أجهزة Android.';

  @override
  String get vpnTitle => 'VPN مجاني (OpenVPN)';

  @override
  String get vpnStateConnected => 'متصل';

  @override
  String get vpnStateBusy => 'جارٍ المعالجة';

  @override
  String get vpnStateError => 'خطأ';

  @override
  String get vpnStateUnsupported => 'غير مدعوم';

  @override
  String get vpnStateOff => 'غير متصل';

  @override
  String vpnConnectedTo(String name) {
    return 'متصل بـ $name';
  }

  @override
  String vpnConnecting(String stage) {
    return 'جارٍ الاتصال… ($stage)';
  }

  @override
  String get vpnDisconnectedHint =>
      'اختر خادماً مجانياً أو استورد ملف .ovpn للاتصال المشفر';

  @override
  String get vpnPickServer => 'اختر خادماً مجانياً';

  @override
  String get vpnServersTitle => 'خوادم مجانية عامة (VPNGate)';

  @override
  String get vpnServersFail => 'تعذر جلب قائمة الخوادم — تحقق من الاتصال';

  @override
  String get vpnNoServers => 'لا توجد خوادم متاحة حالياً';

  @override
  String get vpnImport => 'استيراد .ovpn';

  @override
  String get vpnImportedFile => 'ملف مستورد';

  @override
  String get vpnInvalidConfig => 'الملف ليس إعداد OpenVPN صالحاً';

  @override
  String get vpnDisconnect => 'قطع الاتصال';

  @override
  String vpnReconnect(String name) {
    return 'إعادة الاتصال: $name';
  }

  @override
  String get vpnConnectFailed => 'فشل الاتصال — جرّب خادماً آخر';

  @override
  String get vpnError => 'حدث خطأ أثناء الاتصال. جرّب خادماً آخر.';

  @override
  String get vpnUnsupported =>
      'عميل VPN يعمل على أجهزة Android فقط (يتطلب إذن النظام).';

  @override
  String get didYouMeanPrefix => 'هل تقصد';

  @override
  String get activityTitle => 'نشاطي الذكي';

  @override
  String get activityEmptyTitle => 'لا بيانات نشاط بعد';

  @override
  String get activityEmptyBody =>
      'شاهد بعض الفيديوهات وستظهر إحصائياتك الذكية هنا تلقائياً.';

  @override
  String get activityFailed => 'تعذر حساب الإحصائيات';

  @override
  String get statWatchTime => 'وقت المشاهدة';

  @override
  String get statWatched => 'فيديو شوهد';

  @override
  String get statCompleted => 'اكتملت مشاهدة';

  @override
  String get statStreak => 'سلسلة الأيام';

  @override
  String get hoursUnit => 'ساعة';

  @override
  String get minutesUnit => 'دقيقة';

  @override
  String get daysUnit => 'أيام';

  @override
  String bestStreak(int days) {
    return 'أطول سلسلة مشاهدة: $days يوماً';
  }

  @override
  String peakHourLabel(int hour) {
    return 'ساعة الذروة: $hour:00';
  }

  @override
  String get trend14Title => 'نشاط آخر 14 يوماً';

  @override
  String get trend14Caption => 'ارتفاع كل عمود يمثل وقت المشاهدة في ذلك اليوم';

  @override
  String get weekdayPatternTitle => 'توزيع المشاهدة على أيام الأسبوع';

  @override
  String get weekdayMon => 'الاثنين';

  @override
  String get weekdayTue => 'الثلاثاء';

  @override
  String get weekdayWed => 'الأربعاء';

  @override
  String get weekdayThu => 'الخميس';

  @override
  String get weekdayFri => 'الجمعة';

  @override
  String get weekdaySat => 'السبت';

  @override
  String get weekdaySun => 'الأحد';

  @override
  String get topInterestsTitle => 'اهتماماتك الأبرز';

  @override
  String get cleanupTitle => 'التنظيف الذكي';

  @override
  String get cleanupNoDuplicates => 'لا توجد مكررات';

  @override
  String get cleanupNoDuplicatesBody =>
      'مكتبتك نظيفة — لم نعثر على أي فيديوهات مكررة.';

  @override
  String cleanupFoundClusters(int count) {
    return '$count مجموعة مكررات محتملة';
  }

  @override
  String cleanupDeleteSelected(int count) {
    return 'حذف المحدد ($count)';
  }

  @override
  String get cleanupKeepSuggestion => 'النسخة المقترح الاحتفاظ بها';

  @override
  String get cleanupConfirmTitle => 'تأكيد إزالة المكررات';

  @override
  String cleanupConfirmBody(int count) {
    return 'سيُزال $count عنصر من المكتبة. لن تُحذف أي ملفات من جهازك.';
  }

  @override
  String cleanupDeleted(int count) {
    return 'أُزيل $count عنصر مكرر';
  }

  @override
  String get cleanupFailed => 'فشل التنظيف';

  @override
  String get sleepCustomMinutes => 'دقائق مخصصة';

  @override
  String get sleepStart => 'بدء';

  @override
  String get sleepFadeNote =>
      'سيخفت الصوت تدريجياً في آخر 10 ثوانٍ قبل التوقف.';

  @override
  String get smartPlaylistsTitle => 'القوائم الذكية';

  @override
  String get smartContinueWatching => 'متابعة المشاهدة';

  @override
  String get smartUnwatched => 'لم تُشاهد بعد';

  @override
  String get smartMostPlayed => 'الأكثر تشغيلاً';

  @override
  String get smartRecentlyPlayed => 'شوهدت مؤخراً';

  @override
  String get smartFavorites => 'قائمة المفضلة';

  @override
  String smartBecauseYouWatched(String title) {
    return 'لأنك شاهدت $title';
  }

  @override
  String get smartSaveAsPlaylist => 'حفظ كقائمة تشغيل';

  @override
  String get smartPlaylistSaved => 'حُفظت القائمة في قوائمك';

  @override
  String get smartPlayAll => 'تشغيل الكل';

  @override
  String get settingsBackup => 'النسخ الاحتياطي والاستعادة';

  @override
  String get backupTitle => 'النسخ الاحتياطي والاستعادة';

  @override
  String get backupIncludesTitle => 'ما يشمله ملف النسخة';

  @override
  String backupItemsCount(int count) {
    return '$count عنصر في المكتبة';
  }

  @override
  String backupPlaylistsCount(int count) {
    return '$count قائمة تشغيل';
  }

  @override
  String backupProgressCount(int count) {
    return '$count موضع مشاهدة محفوظ';
  }

  @override
  String backupSearchesCount(int count) {
    return '$count عملية بحث محفوظة';
  }

  @override
  String get backupSettingsRow => 'جميع الإعدادات والتفضيلات';

  @override
  String get backupNeverDeletes =>
      'الاستعادة تضيف فقط ولا تحذف شيئًا من بياناتك الحالية.';

  @override
  String get backupExport => 'تصدير نسخة احتياطية';

  @override
  String backupExportedTo(String path) {
    return 'تم إنشاء الملف: $path';
  }

  @override
  String get backupExportDone =>
      'تم إنشاء النسخة الاحتياطية — شاركها واحفظها في مكان آمن';

  @override
  String get backupImport => 'استعادة من ملف نسخة';

  @override
  String get backupMergeNote =>
      'الاستعادة تدمج البيانات مع مكتبتك: العناصر الموجودة مسبقًا تُتجاهل ولا يُحذف شيء.';

  @override
  String get backupConfirmTitle => 'استعادة هذه النسخة؟';

  @override
  String backupConfirmBody(String version, String date) {
    return 'نسخة من إصدار $version بتاريخ $date. سيتم دمج بياناتها مع مكتبتك الحالية.';
  }

  @override
  String get backupConfirmRestore => 'استعادة';

  @override
  String get backupImportDoneTitle => 'اكتملت الاستعادة';

  @override
  String backupImportDone(int added, int skipped, int playlists, int merged,
      int progress, int searches) {
    return 'أُضيف $added عنصرًا وتجاهُل $skipped موجود مسبقًا • قوائم جديدة $playlists ومدمجة $merged • مواضع مشاهدة $progress • عمليات بحث $searches';
  }

  @override
  String backupFailed(String error) {
    return 'فشل النسخ الاحتياطي: $error';
  }

  @override
  String get sortPlayCount => 'الأكثر تشغيلاً';

  @override
  String get sortResolution => 'دقة الفيديو';

  @override
  String get sortDirectionAscending => 'ترتيب تصاعدي';

  @override
  String get sortDirectionDescending => 'ترتيب تنازلي';

  @override
  String get streamKindHls => 'بث مباشر HLS — سيُشغّل فورًا';

  @override
  String get streamKindDash => 'بث DASH — سيُشغّل فورًا';

  @override
  String get streamKindFile => 'ملف فيديو مباشر';

  @override
  String get analyticsExport => 'تصدير التحليلات';

  @override
  String get analyticsExportCsv => 'تصدير CSV كامل';

  @override
  String get analyticsExportCsvDesc =>
      'جميع عناصر مكتبتك مع مشاهداتها ومواضعها — يفتح في Excel';

  @override
  String get analyticsExportSummary => 'مشاركة ملخص النشاط';

  @override
  String get analyticsExportSummaryDesc =>
      'نص جاهز للمشاركة: وقت المشاهدة، السلاسل، ساعة الذروة';

  @override
  String get downloadsRetryAll => 'إعادة محاولة الفاشلة كلها';

  @override
  String get setAutoResumeWifi => 'استئناف تلقائي عند عودة Wi-Fi';

  @override
  String get setAutoResumeWifiDesc =>
      'يُكمل التنزيلات المتوقفة بسبب انقطاع الشبكة — ما أوقفته بنفسك يبقى متوقفًا';

  @override
  String get cloudBackupTitle => 'النسخ السحابي (WebDAV/SFTP)';

  @override
  String get cloudRefresh => 'تحديث القائمة';

  @override
  String get cloudKindWebdav => 'WebDAV';

  @override
  String get cloudKindSftp => 'SFTP';

  @override
  String get cloudHost => 'العنوان (host)';

  @override
  String get cloudPort => 'المنفذ';

  @override
  String get cloudTls => 'HTTPS';

  @override
  String get cloudUser => 'اسم المستخدم';

  @override
  String get cloudPassword => 'كلمة المرور';

  @override
  String get cloudBasePath => 'المسار الأساسي (اختياري)';

  @override
  String cloudPathNote(String path) {
    return 'ستُحفظ النسخ في مجلد $path على الخادم';
  }

  @override
  String get cloudTest => 'اختبار الاتصال';

  @override
  String get cloudTestOk => 'الاتصال ناجح — المجلد جاهز';

  @override
  String get cloudUploadNow => 'رفع نسخة الآن';

  @override
  String cloudUploaded(String path) {
    return 'رُفعت إلى: $path';
  }

  @override
  String cloudFailed(String error) {
    return 'فشلت العملية: $error';
  }

  @override
  String get cloudAutoTitle => 'نسخ احتياطي تلقائي يومي';

  @override
  String get cloudAutoDesc =>
      'يُرفع ملف نسخة احتياطية تلقائيًا كل 24 ساعة عند فتح شاشة النسخ';

  @override
  String get cloudAutoNeedsConfig => 'أضف خادمًا أولًا لتفعيل النسخ التلقائي';

  @override
  String cloudLastBackup(String stamp) {
    return 'آخر نسخة سحابية: $stamp';
  }

  @override
  String get cloudRemoteList => 'النسخ الموجودة على الخادم';

  @override
  String get cloudListHint => 'اضغط لجلب قائمة النسخ السحابية';

  @override
  String get cloudListEmpty => 'لا توجد نسخ على الخادم بعد';

  @override
  String get appLock => 'قفل التطبيق';

  @override
  String get appLockIntro =>
      'احمِ تطبيقك برمز سري. يُطلب الرمز عند فتح التطبيق بعد مغادرته، ولا يُخزَّن الرمز نفسه على الجهاز إطلاقًا — فقط بصمة مشفّرة منه.';

  @override
  String get appLockCreatePin => 'إنشاء رمز سري';

  @override
  String get appLockChangePin => 'تغيير الرمز';

  @override
  String get appLockRemovePin => 'إزالة القفل';

  @override
  String get appLockEnabledTitle => 'القفل مُفعّل';

  @override
  String get appLockEnabledDesc =>
      'سيُطلب الرمز السري عند العودة إلى التطبيق حسب المدة التي تختارها.';

  @override
  String get appLockEnterCurrent => 'أدخل الرمز الحالي';

  @override
  String get appLockChoosePin => 'اختر رمزًا سريًا (4 أرقام)';

  @override
  String get appLockConfirmPin => 'أعد إدخال الرمز للتأكيد';

  @override
  String get appLockPinMismatch => 'الرمزان غير متطابقين — حاول مجددًا';

  @override
  String get appLockSaved => 'تم حفظ الرمز السري';

  @override
  String get appLockRemoved => 'تمت إزالة قفل التطبيق';

  @override
  String get appLockAutoLock => 'إعادة القفل بعد المغادرة';

  @override
  String get appLockImmediate => 'فورًا';

  @override
  String get appLockAfter1m => 'بعد دقيقة';

  @override
  String get appLockAfter5m => 'بعد 5 دقائق';

  @override
  String get lockTitle => 'التطبيق مقفل';

  @override
  String get lockSubtitle => 'أدخل الرمز السري للمتابعة';

  @override
  String get lockWrongPin => 'رمز خاطئ — حاول مجددًا';

  @override
  String lockLockedOut(int seconds) {
    return 'محاولات كثيرة جدًا. انتظر $seconds ثانية';
  }

  @override
  String get lockPrivacyNote =>
      'الرمز محفوظ بصمة مشفّرة (SHA-256 مملّح) داخل الجهاز فقط. إذا نسيت الرمز فستحتاج إلى مسح بيانات التطبيق.';

  @override
  String get playerAbRepeat => 'تكرار المقطع (أ-ب)';

  @override
  String get playerAbInactive => 'لم يُحدَّد مقطع للتكرار بعد';

  @override
  String get playerAbSetStart => 'تعيين البداية (أ)';

  @override
  String get playerAbSetStartHint => 'من موضع التشغيل الحالي';

  @override
  String get playerAbSetEnd => 'تعيين النهاية (ب)';

  @override
  String get playerAbSetEndHint => 'من موضع التشغيل الحالي';

  @override
  String get playerAbTooShort =>
      'المقطع قصير جدًا — حرّك موضع التشغيل ثم أعد التعيين';

  @override
  String get playerAbClear => 'إلغاء التكرار';

  @override
  String get playerAbNote =>
      'مثالي لحفظ القرآن وتعلم اللغات: يعود التشغيل تلقائيًا إلى نقطة البداية عند بلوغ النهاية، حتى لو انتقلت يدويًا بعد نقطة النهاية. لإيقاف التكرار استخدم زر إلغاء التكرار.';

  @override
  String get playerAudio => 'الصوت';

  @override
  String get audioSheetTitle => 'تحسين الصوت';

  @override
  String get audioPresetFlat => 'بدون معادل';

  @override
  String get audioPresetFlatDesc => 'الصوت الأصلي كما هو';

  @override
  String get audioPresetBass => 'تعزيز الباس';

  @override
  String get audioPresetBassDesc => 'أعمق للموسيقى والأفلام على سماعة الهاتف';

  @override
  String get audioPresetVocal => 'تعزيز الحوار';

  @override
  String get audioPresetVocalDesc => 'أوضح للأخبار والمحاضرات والمسلسلات';

  @override
  String get audioPresetNight => 'الوضع الليلي';

  @override
  String get audioPresetNightDesc =>
      'يخفض الدويّ ويرفع وضوح الكلام للسماعات المنخفضة';

  @override
  String get audioPresetMovie => 'سينمائي';

  @override
  String get audioPresetMovieDesc => 'منحنى واسع يمنح إحساس قاعة العرض';

  @override
  String get audioBoost => 'تعزيز مستوى الصوت';

  @override
  String get audioBoostWarning =>
      'تعزيز عالٍ: قد يظهر تشويش في مقاطع مرتفعة الصوت أصلًا';

  @override
  String get audioEnhanceNote =>
      'تُطبَّق الإعدادات فورًا وتُحفظ كافتراض لكل مقطع تفتحه.';

  @override
  String get vaultTitle => 'الخزنة الخاصة';

  @override
  String get vaultLockedTitle => 'الخزنة مقفلة';

  @override
  String get vaultCreatePin => 'أنشئ رمز الخزنة';

  @override
  String get vaultConfirmPin => 'أعد إدخال الرمز للتأكيد';

  @override
  String get vaultSetupHint =>
      'هذا الرمز يحمي مقاطعك المخفية فقط — وهو مستقل عن رمز قفل التطبيق. 4 أرقام.';

  @override
  String get vaultPinMismatch => 'الرمزان غير متطابقين — ابدأ من جديد';

  @override
  String get vaultPinInvalid => 'يجب أن يتكون الرمز من 4 أرقام';

  @override
  String get vaultPinCreated =>
      'تم إنشاء رمز الخزنة. استخدم «إخفاء في الخزنة» من قائمة أي مقطع.';

  @override
  String get vaultPinChanged => 'تم تحديث رمز الخزنة';

  @override
  String get vaultWrongPin => 'رمز الخزنة غير صحيح';

  @override
  String get vaultEnterPin => 'أدخل رمز الخزنة';

  @override
  String vaultLockedOut(int seconds) {
    return 'محاولات كثيرة جدًا. انتظر $seconds ثانية';
  }

  @override
  String get vaultChangePin => 'تغيير رمز الخزنة';

  @override
  String get vaultCurrentPin => 'الرمز الحالي';

  @override
  String get vaultNewPin => 'الرمز الجديد (4 أرقام)';

  @override
  String get vaultLockNow => 'قفل الآن';

  @override
  String get vaultEmpty => 'الخزنة فارغة';

  @override
  String get vaultEmptyHint =>
      'اضغط مطولًا على أي مقطع في المكتبة واختر «إخفاء في الخزنة» لنقله إلى هنا.';

  @override
  String get hideInVault => 'إخفاء في الخزنة';

  @override
  String get unhideFromVault => 'إخراج من الخزنة';

  @override
  String get vaultItemHidden =>
      'تم إخفاء المقطع — تجده في الإعدادات → الخزنة الخاصة';

  @override
  String get vaultItemRestored => 'تمت إعادة المقطع إلى المكتبة';

  @override
  String get vaultRemoveForever => 'حذف نهائي؟';

  @override
  String get vaultRemoveForeverHint =>
      'سيُحذف ملف الفيديو نفسه من الجهاز، وليس مدخله في المكتبة فقط.';

  @override
  String get subtitleToolsTitle => 'أدوات الترجمة';

  @override
  String get subtitleToolsHint =>
      'مزامنة التوقيت + إصلاح ترميز الملفات القديمة';

  @override
  String get subtitleDelayTitle => 'تأخير المزامنة';

  @override
  String get subtitleDelayEarlier => 'تقديم الترجمة';

  @override
  String get subtitleDelayLater => 'تأخير الترجمة';

  @override
  String get subtitleDelayNone => 'لا يوجد تأخير — الترجمة متزامنة';

  @override
  String subtitleDelayShownLater(String value) {
    return 'تظهر الترجمة بعد $value ثانية';
  }

  @override
  String subtitleDelayShownEarlier(String value) {
    return 'تظهر الترجمة قبل $value ثانية';
  }

  @override
  String get subtitleDelayReset => 'تصفير التأخير';

  @override
  String get subtitleEncodingTitle => 'ترميز النص';

  @override
  String get subtitleEncodingHint =>
      'تظهر ملفات الترجمة العربية القديمة بحروف مبعثرة؟ اختر الترميز الصحيح وسيحوّلها DRS Video تلقائيًا إلى عربية سليمة.';

  @override
  String get encAuto => 'كشف تلقائي (موصى به)';

  @override
  String get encUtf8 => 'UTF-8 (الملفات الحديثة)';

  @override
  String get encWin1256 => 'Windows-1256 (عربي قديم)';

  @override
  String get encIso8859 => 'ISO-8859-6 (عربي قديم)';

  @override
  String get encWin1252 => 'Windows-1252 (لاتيني)';

  @override
  String get subtitleLoadExternal => 'تحميل ملف ترجمة';

  @override
  String get subtitleLoadOk => 'تم تحميل الترجمة';

  @override
  String get subtitleLoadFailed => 'تعذر تحميل ملف الترجمة';

  @override
  String get audioOnlyTitle => 'وضع الصوت فقط';

  @override
  String get audioOnlyHint =>
      'إيقاف فك ترميز الفيديو — يوفر البطارية والبيانات';

  @override
  String get audioOnlyNote =>
      'يستمر تشغيل الصوت بينما تعرض الشاشة هذه الصفحة. يُحفظ اختيارك للمقاطع التالية.';

  @override
  String get audioOnlyActive =>
      'وضع الصوت فقط مُفعّل — تم إيقاف فك ترميز الفيديو لتوفير البطارية والبيانات.';

  @override
  String get audioOnlyRestoreVideo => 'استعادة الفيديو';
}
