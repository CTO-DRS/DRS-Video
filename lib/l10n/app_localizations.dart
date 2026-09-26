import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appName.
  ///
  /// In ar, this message translates to:
  /// **'DRS Video'**
  String get appName;

  /// No description provided for @ok.
  ///
  /// In ar, this message translates to:
  /// **'موافق'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In ar, this message translates to:
  /// **'حفظ'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In ar, this message translates to:
  /// **'حذف'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In ar, this message translates to:
  /// **'تعديل'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In ar, this message translates to:
  /// **'إضافة'**
  String get add;

  /// No description provided for @close.
  ///
  /// In ar, this message translates to:
  /// **'إغلاق'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get retry;

  /// No description provided for @details.
  ///
  /// In ar, this message translates to:
  /// **'التفاصيل'**
  String get details;

  /// No description provided for @share.
  ///
  /// In ar, this message translates to:
  /// **'مشاركة'**
  String get share;

  /// No description provided for @rename.
  ///
  /// In ar, this message translates to:
  /// **'إعادة تسمية'**
  String get rename;

  /// No description provided for @copy.
  ///
  /// In ar, this message translates to:
  /// **'نسخ'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In ar, this message translates to:
  /// **'تم النسخ'**
  String get copied;

  /// No description provided for @open.
  ///
  /// In ar, this message translates to:
  /// **'فتح'**
  String get open;

  /// No description provided for @play.
  ///
  /// In ar, this message translates to:
  /// **'تشغيل'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In ar, this message translates to:
  /// **'إيقاف مؤقت'**
  String get pause;

  /// No description provided for @resumeAction.
  ///
  /// In ar, this message translates to:
  /// **'استئناف'**
  String get resumeAction;

  /// No description provided for @stop.
  ///
  /// In ar, this message translates to:
  /// **'إيقاف'**
  String get stop;

  /// No description provided for @done.
  ///
  /// In ar, this message translates to:
  /// **'تم'**
  String get done;

  /// No description provided for @next.
  ///
  /// In ar, this message translates to:
  /// **'التالي'**
  String get next;

  /// No description provided for @previous.
  ///
  /// In ar, this message translates to:
  /// **'السابق'**
  String get previous;

  /// No description provided for @continueWord.
  ///
  /// In ar, this message translates to:
  /// **'متابعة'**
  String get continueWord;

  /// No description provided for @search.
  ///
  /// In ar, this message translates to:
  /// **'بحث'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In ar, this message translates to:
  /// **'تصفية'**
  String get filter;

  /// No description provided for @sort.
  ///
  /// In ar, this message translates to:
  /// **'ترتيب'**
  String get sort;

  /// No description provided for @clear.
  ///
  /// In ar, this message translates to:
  /// **'مسح'**
  String get clear;

  /// No description provided for @loading.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ التحميل…'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In ar, this message translates to:
  /// **'خطأ'**
  String get error;

  /// No description provided for @offline.
  ///
  /// In ar, this message translates to:
  /// **'غير متصل بالإنترنت'**
  String get offline;

  /// No description provided for @online.
  ///
  /// In ar, this message translates to:
  /// **'متصل'**
  String get online;

  /// No description provided for @yes.
  ///
  /// In ar, this message translates to:
  /// **'نعم'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In ar, this message translates to:
  /// **'لا'**
  String get no;

  /// No description provided for @refresh.
  ///
  /// In ar, this message translates to:
  /// **'تحديث'**
  String get refresh;

  /// No description provided for @selectAll.
  ///
  /// In ar, this message translates to:
  /// **'تحديد الكل'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء التحديد'**
  String get deselectAll;

  /// No description provided for @itemsSelected.
  ///
  /// In ar, this message translates to:
  /// **'{count} عنصر محدد'**
  String itemsSelected(int count);

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد الحذف'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteItemsMessage.
  ///
  /// In ar, this message translates to:
  /// **'هل تريد حذف {count} عنصرًا نهائيًا؟'**
  String deleteItemsMessage(int count);

  /// No description provided for @navHome.
  ///
  /// In ar, this message translates to:
  /// **'الرئيسية'**
  String get navHome;

  /// No description provided for @navLibrary.
  ///
  /// In ar, this message translates to:
  /// **'المكتبة'**
  String get navLibrary;

  /// No description provided for @navPlaylists.
  ///
  /// In ar, this message translates to:
  /// **'القوائم'**
  String get navPlaylists;

  /// No description provided for @navDownloads.
  ///
  /// In ar, this message translates to:
  /// **'التنزيلات'**
  String get navDownloads;

  /// No description provided for @navSettings.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get navSettings;

  /// No description provided for @homeSearchHint.
  ///
  /// In ar, this message translates to:
  /// **'ابحث في المكتبة والتنزيلات والملفات…'**
  String get homeSearchHint;

  /// No description provided for @homeContinueWatching.
  ///
  /// In ar, this message translates to:
  /// **'متابعة المشاهدة'**
  String get homeContinueWatching;

  /// No description provided for @homeRecent.
  ///
  /// In ar, this message translates to:
  /// **'أُضيف حديثًا'**
  String get homeRecent;

  /// No description provided for @homeFavorites.
  ///
  /// In ar, this message translates to:
  /// **'المفضلة'**
  String get homeFavorites;

  /// No description provided for @homeRecommended.
  ///
  /// In ar, this message translates to:
  /// **'مقترح لك'**
  String get homeRecommended;

  /// No description provided for @homeDownloads.
  ///
  /// In ar, this message translates to:
  /// **'التنزيلات'**
  String get homeDownloads;

  /// No description provided for @homePlaylists.
  ///
  /// In ar, this message translates to:
  /// **'قوائم التشغيل'**
  String get homePlaylists;

  /// No description provided for @homeSources.
  ///
  /// In ar, this message translates to:
  /// **'المصادر'**
  String get homeSources;

  /// No description provided for @homeLocalFiles.
  ///
  /// In ar, this message translates to:
  /// **'الملفات المحلية'**
  String get homeLocalFiles;

  /// No description provided for @homeQuickActions.
  ///
  /// In ar, this message translates to:
  /// **'إجراءات سريعة'**
  String get homeQuickActions;

  /// No description provided for @homeOpenUrl.
  ///
  /// In ar, this message translates to:
  /// **'فتح رابط فيديو'**
  String get homeOpenUrl;

  /// No description provided for @homeOpenFile.
  ///
  /// In ar, this message translates to:
  /// **'فتح ملف فيديو'**
  String get homeOpenFile;

  /// No description provided for @homeSeeAll.
  ///
  /// In ar, this message translates to:
  /// **'عرض الكل'**
  String get homeSeeAll;

  /// No description provided for @emptyGenericTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد شيء هنا بعد'**
  String get emptyGenericTitle;

  /// No description provided for @emptyLibraryTitle.
  ///
  /// In ar, this message translates to:
  /// **'المكتبة فارغة'**
  String get emptyLibraryTitle;

  /// No description provided for @emptyLibraryBody.
  ///
  /// In ar, this message translates to:
  /// **'أضف رابطًا أو ملفًا محليًا لتبدأ.'**
  String get emptyLibraryBody;

  /// No description provided for @emptyFavoritesTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا مفضلات'**
  String get emptyFavoritesTitle;

  /// No description provided for @emptyFavoritesBody.
  ///
  /// In ar, this message translates to:
  /// **'أضف فيديوهات إلى المفضلة لتجدها هنا.'**
  String get emptyFavoritesBody;

  /// No description provided for @emptyDownloadsTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا تنزيلات'**
  String get emptyDownloadsTitle;

  /// No description provided for @emptyDownloadsBody.
  ///
  /// In ar, this message translates to:
  /// **'افتح رابط فيديو واضغط زر التنزيل لبدء التنزيل.'**
  String get emptyDownloadsBody;

  /// No description provided for @emptyPlaylistsTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا قوائم تشغيل'**
  String get emptyPlaylistsTitle;

  /// No description provided for @emptyPlaylistsBody.
  ///
  /// In ar, this message translates to:
  /// **'أنشئ قائمة تشغيل نظّم بها فيديوهاتك.'**
  String get emptyPlaylistsBody;

  /// No description provided for @emptyHistoryTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا سجل مشاهدة'**
  String get emptyHistoryTitle;

  /// No description provided for @emptyHistoryBody.
  ///
  /// In ar, this message translates to:
  /// **'ستظهر هنا الفيديوهات التي شاهدتها.'**
  String get emptyHistoryBody;

  /// No description provided for @emptyLocalFilesTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا ملفات محلية'**
  String get emptyLocalFilesTitle;

  /// No description provided for @emptyLocalFilesBody.
  ///
  /// In ar, this message translates to:
  /// **'لم نعثر على فيديوهات على الجهاز أو لم يُمنح الإذن بعد.'**
  String get emptyLocalFilesBody;

  /// No description provided for @emptySearchTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا نتائج'**
  String get emptySearchTitle;

  /// No description provided for @emptySearchBody.
  ///
  /// In ar, this message translates to:
  /// **'جرّب كلمات بحث أخرى أو عدّل التصفية.'**
  String get emptySearchBody;

  /// No description provided for @emptyContinueTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا مشاهدات غير مكتملة'**
  String get emptyContinueTitle;

  /// No description provided for @emptyContinueBody.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ بمشاهدة فيديو وستتمكن من متابعته من هنا.'**
  String get emptyContinueBody;

  /// No description provided for @actionPlayFromStart.
  ///
  /// In ar, this message translates to:
  /// **'تشغيل من البداية'**
  String get actionPlayFromStart;

  /// No description provided for @actionAddToPlaylist.
  ///
  /// In ar, this message translates to:
  /// **'إضافة إلى قائمة تشغيل'**
  String get actionAddToPlaylist;

  /// No description provided for @actionRemoveFromPlaylist.
  ///
  /// In ar, this message translates to:
  /// **'إزالة من القائمة'**
  String get actionRemoveFromPlaylist;

  /// No description provided for @actionFavorite.
  ///
  /// In ar, this message translates to:
  /// **'إضافة إلى المفضلة'**
  String get actionFavorite;

  /// No description provided for @actionUnfavorite.
  ///
  /// In ar, this message translates to:
  /// **'إزالة من المفضلة'**
  String get actionUnfavorite;

  /// No description provided for @actionShareLink.
  ///
  /// In ar, this message translates to:
  /// **'مشاركة الرابط'**
  String get actionShareLink;

  /// No description provided for @actionShareFile.
  ///
  /// In ar, this message translates to:
  /// **'مشاركة الملف'**
  String get actionShareFile;

  /// No description provided for @actionCopyLink.
  ///
  /// In ar, this message translates to:
  /// **'نسخ الرابط'**
  String get actionCopyLink;

  /// No description provided for @actionOpenWith.
  ///
  /// In ar, this message translates to:
  /// **'فتح باستخدام'**
  String get actionOpenWith;

  /// No description provided for @actionFileInfo.
  ///
  /// In ar, this message translates to:
  /// **'معلومات الملف'**
  String get actionFileInfo;

  /// No description provided for @actionDownload.
  ///
  /// In ar, this message translates to:
  /// **'تنزيل'**
  String get actionDownload;

  /// No description provided for @actionNewPlaylist.
  ///
  /// In ar, this message translates to:
  /// **'قائمة تشغيل جديدة'**
  String get actionNewPlaylist;

  /// No description provided for @actionExport.
  ///
  /// In ar, this message translates to:
  /// **'تصدير'**
  String get actionExport;

  /// No description provided for @actionImport.
  ///
  /// In ar, this message translates to:
  /// **'استيراد'**
  String get actionImport;

  /// No description provided for @playerQuality.
  ///
  /// In ar, this message translates to:
  /// **'الجودة'**
  String get playerQuality;

  /// No description provided for @playerSpeed.
  ///
  /// In ar, this message translates to:
  /// **'السرعة'**
  String get playerSpeed;

  /// No description provided for @playerAudioTrack.
  ///
  /// In ar, this message translates to:
  /// **'المسار الصوتي'**
  String get playerAudioTrack;

  /// No description provided for @playerSubtitleTrack.
  ///
  /// In ar, this message translates to:
  /// **'الترجمة'**
  String get playerSubtitleTrack;

  /// No description provided for @playerAddSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'إضافة ملف ترجمة'**
  String get playerAddSubtitle;

  /// No description provided for @playerSleepTimer.
  ///
  /// In ar, this message translates to:
  /// **'مؤقت النوم'**
  String get playerSleepTimer;

  /// No description provided for @playerOff.
  ///
  /// In ar, this message translates to:
  /// **'إيقاف'**
  String get playerOff;

  /// No description provided for @playerEndOfVideo.
  ///
  /// In ar, this message translates to:
  /// **'نهاية الفيديو'**
  String get playerEndOfVideo;

  /// No description provided for @playerMinutes.
  ///
  /// In ar, this message translates to:
  /// **'{count} دقيقة'**
  String playerMinutes(int count);

  /// No description provided for @playerPiP.
  ///
  /// In ar, this message translates to:
  /// **'نافذة عائمة (PiP)'**
  String get playerPiP;

  /// No description provided for @playerLock.
  ///
  /// In ar, this message translates to:
  /// **'قفل التحكم'**
  String get playerLock;

  /// No description provided for @playerUnlock.
  ///
  /// In ar, this message translates to:
  /// **'فتح التحكم'**
  String get playerUnlock;

  /// No description provided for @playerFullscreen.
  ///
  /// In ar, this message translates to:
  /// **'ملء الشاشة'**
  String get playerFullscreen;

  /// No description provided for @playerAuto.
  ///
  /// In ar, this message translates to:
  /// **'تلقائي'**
  String get playerAuto;

  /// No description provided for @playerSingleQuality.
  ///
  /// In ar, this message translates to:
  /// **'يوفر المصدر جودة واحدة فقط'**
  String get playerSingleQuality;

  /// No description provided for @playerNoAudioTracks.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد مسارات صوتية إضافية'**
  String get playerNoAudioTracks;

  /// No description provided for @playerNoSubtitleTracks.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد ترجمات — يمكنك إضافة ملف ترجمة'**
  String get playerNoSubtitleTracks;

  /// No description provided for @playerExternalSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'ملف خارجي'**
  String get playerExternalSubtitle;

  /// No description provided for @playerSubLoaded.
  ///
  /// In ar, this message translates to:
  /// **'تم تحميل ملف الترجمة'**
  String get playerSubLoaded;

  /// No description provided for @playerSubInvalid.
  ///
  /// In ar, this message translates to:
  /// **'ملف الترجمة غير صالح أو فارغ'**
  String get playerSubInvalid;

  /// No description provided for @playerBuffering.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ التخزين المؤقت…'**
  String get playerBuffering;

  /// No description provided for @playerErrorTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعذر تشغيل الفيديو'**
  String get playerErrorTitle;

  /// No description provided for @playerErrorNetwork.
  ///
  /// In ar, this message translates to:
  /// **'تعذر الوصول إلى الرابط. تحقق من اتصالك بالإنترنت وصحة الرابط.'**
  String get playerErrorNetwork;

  /// No description provided for @playerErrorTimeout.
  ///
  /// In ar, this message translates to:
  /// **'استغرق المصدر وقتًا طويلًا للاستجابة.'**
  String get playerErrorTimeout;

  /// No description provided for @playerErrorUnsupported.
  ///
  /// In ar, this message translates to:
  /// **'صيغة الفيديو غير مدعومة على هذا الجهاز.'**
  String get playerErrorUnsupported;

  /// No description provided for @playerErrorCorrupted.
  ///
  /// In ar, this message translates to:
  /// **'الملف تالف أو غير مكتمل.'**
  String get playerErrorCorrupted;

  /// No description provided for @playerErrorNotFound.
  ///
  /// In ar, this message translates to:
  /// **'الملف أو الرابط غير موجود (404).'**
  String get playerErrorNotFound;

  /// No description provided for @playerErrorForbidden.
  ///
  /// In ar, this message translates to:
  /// **'المصدر يمنع التشغيل من خارج موقعه.'**
  String get playerErrorForbidden;

  /// No description provided for @playerErrorUnknown.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ غير متوقع أثناء التشغيل.'**
  String get playerErrorUnknown;

  /// No description provided for @playerResumeFrom.
  ///
  /// In ar, this message translates to:
  /// **'متابعة من {time}؟'**
  String playerResumeFrom(String time);

  /// No description provided for @playerStartOver.
  ///
  /// In ar, this message translates to:
  /// **'من البداية'**
  String get playerStartOver;

  /// No description provided for @playerBrightness.
  ///
  /// In ar, this message translates to:
  /// **'السطوع'**
  String get playerBrightness;

  /// No description provided for @playerVolume.
  ///
  /// In ar, this message translates to:
  /// **'الصوت'**
  String get playerVolume;

  /// No description provided for @playerFrameStepHint.
  ///
  /// In ar, this message translates to:
  /// **'خطوة إطار'**
  String get playerFrameStepHint;

  /// No description provided for @playerSkipIntro.
  ///
  /// In ar, this message translates to:
  /// **'تخطي المقدمة'**
  String get playerSkipIntro;

  /// No description provided for @playerSkipOutro.
  ///
  /// In ar, this message translates to:
  /// **'تخطي الخاتمة'**
  String get playerSkipOutro;

  /// No description provided for @playerNextVideo.
  ///
  /// In ar, this message translates to:
  /// **'الفيديو التالي'**
  String get playerNextVideo;

  /// No description provided for @playerPrevVideo.
  ///
  /// In ar, this message translates to:
  /// **'الفيديو السابق'**
  String get playerPrevVideo;

  /// No description provided for @playerCompleted.
  ///
  /// In ar, this message translates to:
  /// **'اكتمل التشغيل'**
  String get playerCompleted;

  /// No description provided for @downloadsActive.
  ///
  /// In ar, this message translates to:
  /// **'قيد التنزيل'**
  String get downloadsActive;

  /// No description provided for @downloadsQueued.
  ///
  /// In ar, this message translates to:
  /// **'في الانتظار'**
  String get downloadsQueued;

  /// No description provided for @downloadsCompleted.
  ///
  /// In ar, this message translates to:
  /// **'مكتملة'**
  String get downloadsCompleted;

  /// No description provided for @downloadsFailed.
  ///
  /// In ar, this message translates to:
  /// **'فاشلة'**
  String get downloadsFailed;

  /// No description provided for @downloadsPauseAll.
  ///
  /// In ar, this message translates to:
  /// **'إيقاف الكل مؤقتًا'**
  String get downloadsPauseAll;

  /// No description provided for @downloadsResumeAll.
  ///
  /// In ar, this message translates to:
  /// **'استئناف الكل'**
  String get downloadsResumeAll;

  /// No description provided for @downloadsPriority.
  ///
  /// In ar, this message translates to:
  /// **'الأولوية'**
  String get downloadsPriority;

  /// No description provided for @downloadsPriorityHigh.
  ///
  /// In ar, this message translates to:
  /// **'عالية'**
  String get downloadsPriorityHigh;

  /// No description provided for @downloadsPriorityNormal.
  ///
  /// In ar, this message translates to:
  /// **'عادية'**
  String get downloadsPriorityNormal;

  /// No description provided for @downloadsPriorityLow.
  ///
  /// In ar, this message translates to:
  /// **'منخفضة'**
  String get downloadsPriorityLow;

  /// No description provided for @downloadsFreeSpace.
  ///
  /// In ar, this message translates to:
  /// **'المساحة المتاحة: {size}'**
  String downloadsFreeSpace(String size);

  /// No description provided for @downloadsCorruptedFile.
  ///
  /// In ar, this message translates to:
  /// **'يبدو أن الملف غير مكتمل — أعد المحاولة للإصلاح.'**
  String get downloadsCorruptedFile;

  /// No description provided for @downloadStarted.
  ///
  /// In ar, this message translates to:
  /// **'بدأ التنزيل'**
  String get downloadStarted;

  /// No description provided for @downloadCompletedNotif.
  ///
  /// In ar, this message translates to:
  /// **'اكتمل التنزيل'**
  String get downloadCompletedNotif;

  /// No description provided for @downloadFailedNotif.
  ///
  /// In ar, this message translates to:
  /// **'فشل التنزيل'**
  String get downloadFailedNotif;

  /// No description provided for @downloadsWifiOnlyWarning.
  ///
  /// In ar, this message translates to:
  /// **'التنزيل عبر Wi-Fi فقط مُفعّل — انتظر اتصال Wi-Fi.'**
  String get downloadsWifiOnlyWarning;

  /// No description provided for @downloadsInsufficientSpace.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد مساحة تخزين كافية.'**
  String get downloadsInsufficientSpace;

  /// No description provided for @downloadsServerNoResume.
  ///
  /// In ar, this message translates to:
  /// **'الخادم لا يدعم استكمال التنزيل؛ سيبدأ من جديد عند الاستئناف.'**
  String get downloadsServerNoResume;

  /// No description provided for @libraryAll.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get libraryAll;

  /// No description provided for @libraryFavorites.
  ///
  /// In ar, this message translates to:
  /// **'المفضلة'**
  String get libraryFavorites;

  /// No description provided for @libraryDownloads.
  ///
  /// In ar, this message translates to:
  /// **'التنزيلات'**
  String get libraryDownloads;

  /// No description provided for @libraryRecent.
  ///
  /// In ar, this message translates to:
  /// **'الأحدث'**
  String get libraryRecent;

  /// No description provided for @libraryContinue.
  ///
  /// In ar, this message translates to:
  /// **'المتابعة'**
  String get libraryContinue;

  /// No description provided for @libraryLocal.
  ///
  /// In ar, this message translates to:
  /// **'المحلية'**
  String get libraryLocal;

  /// No description provided for @libraryHistory.
  ///
  /// In ar, this message translates to:
  /// **'السجل'**
  String get libraryHistory;

  /// No description provided for @librarySortBy.
  ///
  /// In ar, this message translates to:
  /// **'الترتيب حسب'**
  String get librarySortBy;

  /// No description provided for @sortName.
  ///
  /// In ar, this message translates to:
  /// **'الاسم'**
  String get sortName;

  /// No description provided for @sortDateAdded.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ الإضافة'**
  String get sortDateAdded;

  /// No description provided for @sortRecentlyPlayed.
  ///
  /// In ar, this message translates to:
  /// **'آخر مشاهدة'**
  String get sortRecentlyPlayed;

  /// No description provided for @sortDuration.
  ///
  /// In ar, this message translates to:
  /// **'المدة'**
  String get sortDuration;

  /// No description provided for @sortSize.
  ///
  /// In ar, this message translates to:
  /// **'الحجم'**
  String get sortSize;

  /// No description provided for @filterType.
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get filterType;

  /// No description provided for @filterSource.
  ///
  /// In ar, this message translates to:
  /// **'المصدر'**
  String get filterSource;

  /// No description provided for @filterDuration.
  ///
  /// In ar, this message translates to:
  /// **'المدة'**
  String get filterDuration;

  /// No description provided for @filterFavoritesOnly.
  ///
  /// In ar, this message translates to:
  /// **'المفضلة فقط'**
  String get filterFavoritesOnly;

  /// No description provided for @durationShort.
  ///
  /// In ar, this message translates to:
  /// **'أقل من 5 دقائق'**
  String get durationShort;

  /// No description provided for @durationMedium.
  ///
  /// In ar, this message translates to:
  /// **'5 – 20 دقيقة'**
  String get durationMedium;

  /// No description provided for @durationLong.
  ///
  /// In ar, this message translates to:
  /// **'20 – 60 دقيقة'**
  String get durationLong;

  /// No description provided for @durationVeryLong.
  ///
  /// In ar, this message translates to:
  /// **'أكثر من ساعة'**
  String get durationVeryLong;

  /// No description provided for @typeAll.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get typeAll;

  /// No description provided for @typeLocal.
  ///
  /// In ar, this message translates to:
  /// **'ملف محلي'**
  String get typeLocal;

  /// No description provided for @typeNetwork.
  ///
  /// In ar, this message translates to:
  /// **'رابط'**
  String get typeNetwork;

  /// No description provided for @typeDownload.
  ///
  /// In ar, this message translates to:
  /// **'تنزيل'**
  String get typeDownload;

  /// No description provided for @multiSelectTitle.
  ///
  /// In ar, this message translates to:
  /// **'تحديد متعدد'**
  String get multiSelectTitle;

  /// No description provided for @playlistsCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} فيديو'**
  String playlistsCount(int count);

  /// No description provided for @playlistNameHint.
  ///
  /// In ar, this message translates to:
  /// **'اسم القائمة'**
  String get playlistNameHint;

  /// No description provided for @playlistPlayAll.
  ///
  /// In ar, this message translates to:
  /// **'تشغيل القائمة'**
  String get playlistPlayAll;

  /// No description provided for @playlistShuffle.
  ///
  /// In ar, this message translates to:
  /// **'تشغيل عشوائي'**
  String get playlistShuffle;

  /// No description provided for @playlistRepeat.
  ///
  /// In ar, this message translates to:
  /// **'التكرار'**
  String get playlistRepeat;

  /// No description provided for @repeatOff.
  ///
  /// In ar, this message translates to:
  /// **'بدون تكرار'**
  String get repeatOff;

  /// No description provided for @repeatAll.
  ///
  /// In ar, this message translates to:
  /// **'تكرار القائمة'**
  String get repeatAll;

  /// No description provided for @repeatOne.
  ///
  /// In ar, this message translates to:
  /// **'تكرار الحالي'**
  String get repeatOne;

  /// No description provided for @playlistReorderHint.
  ///
  /// In ar, this message translates to:
  /// **'اسحب لإعادة الترتيب'**
  String get playlistReorderHint;

  /// No description provided for @playlistExported.
  ///
  /// In ar, this message translates to:
  /// **'تم تصدير القائمة للمشاركة'**
  String get playlistExported;

  /// No description provided for @playlistImported.
  ///
  /// In ar, this message translates to:
  /// **'تم استيراد القائمة'**
  String get playlistImported;

  /// No description provided for @playlistInvalidFile.
  ///
  /// In ar, this message translates to:
  /// **'ملف القائمة غير صالح'**
  String get playlistInvalidFile;

  /// No description provided for @playlistPickVideos.
  ///
  /// In ar, this message translates to:
  /// **'اختر فيديوهات للإضافة'**
  String get playlistPickVideos;

  /// No description provided for @searchHint.
  ///
  /// In ar, this message translates to:
  /// **'ابحث بالعنوان أو المصدر…'**
  String get searchHint;

  /// No description provided for @searchSuggestions.
  ///
  /// In ar, this message translates to:
  /// **'اقتراحات'**
  String get searchSuggestions;

  /// No description provided for @searchRecentQueries.
  ///
  /// In ar, this message translates to:
  /// **'أبحاث سابقة'**
  String get searchRecentQueries;

  /// No description provided for @searchResults.
  ///
  /// In ar, this message translates to:
  /// **'النتائج'**
  String get searchResults;

  /// No description provided for @searchClearHistory.
  ///
  /// In ar, this message translates to:
  /// **'مسح سجل البحث'**
  String get searchClearHistory;

  /// No description provided for @sourcesTitle.
  ///
  /// In ar, this message translates to:
  /// **'المصادر'**
  String get sourcesTitle;

  /// No description provided for @sourcesLocalAdapter.
  ///
  /// In ar, this message translates to:
  /// **'الملفات المحلية'**
  String get sourcesLocalAdapter;

  /// No description provided for @sourcesLocalAdapterDesc.
  ///
  /// In ar, this message translates to:
  /// **'فيديوهات الجهاز عبر MediaStore'**
  String get sourcesLocalAdapterDesc;

  /// No description provided for @sourcesDirectAdapter.
  ///
  /// In ar, this message translates to:
  /// **'روابط مباشرة'**
  String get sourcesDirectAdapter;

  /// No description provided for @sourcesDirectAdapterDesc.
  ///
  /// In ar, this message translates to:
  /// **'ملفات MP4 / MKV / WebM وروابط HLS المباشرة'**
  String get sourcesDirectAdapterDesc;

  /// No description provided for @sourcesAddTitle.
  ///
  /// In ar, this message translates to:
  /// **'إضافة مصدر'**
  String get sourcesAddTitle;

  /// No description provided for @sourcesNameHint.
  ///
  /// In ar, this message translates to:
  /// **'اسم المصدر'**
  String get sourcesNameHint;

  /// No description provided for @sourcesBaseUrlHint.
  ///
  /// In ar, this message translates to:
  /// **'عنوان المصدر الأساسي (https://…)'**
  String get sourcesBaseUrlHint;

  /// No description provided for @sourcesHeaderHint.
  ///
  /// In ar, this message translates to:
  /// **'ترويسة اختيارية (مثل Authorization: Bearer …)'**
  String get sourcesHeaderHint;

  /// No description provided for @sourcesTest.
  ///
  /// In ar, this message translates to:
  /// **'اختبار الاتصال'**
  String get sourcesTest;

  /// No description provided for @sourcesTestOk.
  ///
  /// In ar, this message translates to:
  /// **'الاتصال ناجح'**
  String get sourcesTestOk;

  /// No description provided for @sourcesTestFail.
  ///
  /// In ar, this message translates to:
  /// **'فشل الاتصال'**
  String get sourcesTestFail;

  /// No description provided for @sourcesEnabled.
  ///
  /// In ar, this message translates to:
  /// **'مفعّل'**
  String get sourcesEnabled;

  /// No description provided for @sourcesDisabled.
  ///
  /// In ar, this message translates to:
  /// **'معطّل'**
  String get sourcesDisabled;

  /// No description provided for @sourcesDeleteWarn.
  ///
  /// In ar, this message translates to:
  /// **'سيُحذف المصدر فقط، ولن تُحذف الفيديوهات المحفوظة.'**
  String get sourcesDeleteWarn;

  /// No description provided for @sourcesPrivacyNote.
  ///
  /// In ar, this message translates to:
  /// **'لا يدعم التطبيق تجاوز حماية أي منصة؛ يعمل فقط مع المصادر التي تسمح رسميًا بالوصول المباشر.'**
  String get sourcesPrivacyNote;

  /// No description provided for @localFilesPermissionNeeded.
  ///
  /// In ar, this message translates to:
  /// **'إذن الوصول إلى الوسائط مطلوب لعرض فيديوهات الجهاز.'**
  String get localFilesPermissionNeeded;

  /// No description provided for @localFilesGrant.
  ///
  /// In ar, this message translates to:
  /// **'منح الإذن'**
  String get localFilesGrant;

  /// No description provided for @localFilesScanning.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ فحص الوسائط…'**
  String get localFilesScanning;

  /// No description provided for @fileInfoTitle.
  ///
  /// In ar, this message translates to:
  /// **'معلومات الملف'**
  String get fileInfoTitle;

  /// No description provided for @fileInfoPath.
  ///
  /// In ar, this message translates to:
  /// **'المسار'**
  String get fileInfoPath;

  /// No description provided for @fileInfoSize.
  ///
  /// In ar, this message translates to:
  /// **'الحجم'**
  String get fileInfoSize;

  /// No description provided for @fileInfoDuration.
  ///
  /// In ar, this message translates to:
  /// **'المدة'**
  String get fileInfoDuration;

  /// No description provided for @fileInfoAdded.
  ///
  /// In ar, this message translates to:
  /// **'أُضيف في'**
  String get fileInfoAdded;

  /// No description provided for @fileInfoLastPlayed.
  ///
  /// In ar, this message translates to:
  /// **'آخر مشاهدة'**
  String get fileInfoLastPlayed;

  /// No description provided for @fileInfoTimesPlayed.
  ///
  /// In ar, this message translates to:
  /// **'مرات التشغيل'**
  String get fileInfoTimesPlayed;

  /// No description provided for @settingsPlayback.
  ///
  /// In ar, this message translates to:
  /// **'التشغيل'**
  String get settingsPlayback;

  /// No description provided for @settingsDownloads.
  ///
  /// In ar, this message translates to:
  /// **'التنزيلات'**
  String get settingsDownloads;

  /// No description provided for @settingsAppearance.
  ///
  /// In ar, this message translates to:
  /// **'المظهر'**
  String get settingsAppearance;

  /// No description provided for @settingsStorage.
  ///
  /// In ar, this message translates to:
  /// **'التخزين'**
  String get settingsStorage;

  /// No description provided for @settingsPrivacy.
  ///
  /// In ar, this message translates to:
  /// **'الخصوصية'**
  String get settingsPrivacy;

  /// No description provided for @settingsNotifications.
  ///
  /// In ar, this message translates to:
  /// **'الإشعارات'**
  String get settingsNotifications;

  /// No description provided for @settingsAbout.
  ///
  /// In ar, this message translates to:
  /// **'حول التطبيق'**
  String get settingsAbout;

  /// No description provided for @setDefaultQuality.
  ///
  /// In ar, this message translates to:
  /// **'الجودة الافتراضية'**
  String get setDefaultQuality;

  /// No description provided for @qualityAuto.
  ///
  /// In ar, this message translates to:
  /// **'تلقائي حسب الاتصال'**
  String get qualityAuto;

  /// No description provided for @qualityHigh.
  ///
  /// In ar, this message translates to:
  /// **'أعلى جودة'**
  String get qualityHigh;

  /// No description provided for @qualityMedium.
  ///
  /// In ar, this message translates to:
  /// **'متوسطة'**
  String get qualityMedium;

  /// No description provided for @qualityLow.
  ///
  /// In ar, this message translates to:
  /// **'موفر للبيانات'**
  String get qualityLow;

  /// No description provided for @setDefaultSpeed.
  ///
  /// In ar, this message translates to:
  /// **'سرعة التشغيل الافتراضية'**
  String get setDefaultSpeed;

  /// No description provided for @setAutoPlayNext.
  ///
  /// In ar, this message translates to:
  /// **'تشغيل التالي تلقائيًا'**
  String get setAutoPlayNext;

  /// No description provided for @setAutoPlayNextDesc.
  ///
  /// In ar, this message translates to:
  /// **'بدء الفيديو التالي في قائمة الانتظار عند الانتهاء'**
  String get setAutoPlayNextDesc;

  /// No description provided for @setAlwaysResume.
  ///
  /// In ar, this message translates to:
  /// **'استكمال المشاهدة دائمًا'**
  String get setAlwaysResume;

  /// No description provided for @setAlwaysResumeDesc.
  ///
  /// In ar, this message translates to:
  /// **'الاستئناف من آخر موضع دون سؤال'**
  String get setAlwaysResumeDesc;

  /// No description provided for @setPip.
  ///
  /// In ar, this message translates to:
  /// **'نافذة عائمة PiP'**
  String get setPip;

  /// No description provided for @setPipDesc.
  ///
  /// In ar, this message translates to:
  /// **'مشاهدة الفيديو في نافذة صغيرة أثناء التنقل'**
  String get setPipDesc;

  /// No description provided for @setAutoPip.
  ///
  /// In ar, this message translates to:
  /// **'PiP تلقائي عند الخروج'**
  String get setAutoPip;

  /// No description provided for @setAutoPipDesc.
  ///
  /// In ar, this message translates to:
  /// **'التحول إلى النافذة العائمة عند مغادرة التطبيق (أندرويد 12+)'**
  String get setAutoPipDesc;

  /// No description provided for @setBackground.
  ///
  /// In ar, this message translates to:
  /// **'تشغيل في الخلفية'**
  String get setBackground;

  /// No description provided for @setBackgroundDesc.
  ///
  /// In ar, this message translates to:
  /// **'استمرار الصوت مع إشعار وسائط عند تصغير التطبيق'**
  String get setBackgroundDesc;

  /// No description provided for @setPreferFullscreen.
  ///
  /// In ar, this message translates to:
  /// **'البدء بملء الشاشة'**
  String get setPreferFullscreen;

  /// No description provided for @setDownloadFolder.
  ///
  /// In ar, this message translates to:
  /// **'مجلد التنزيل'**
  String get setDownloadFolder;

  /// No description provided for @setDownloadFolderDesc.
  ///
  /// In ar, this message translates to:
  /// **'افتراضيًا يُحفظ داخل مجلد التطبيق الخاص دون أذونات'**
  String get setDownloadFolderDesc;

  /// No description provided for @setUseCustomFolder.
  ///
  /// In ar, this message translates to:
  /// **'اختيار مجلد مخصص'**
  String get setUseCustomFolder;

  /// No description provided for @setCustomFolderNeedsAllFiles.
  ///
  /// In ar, this message translates to:
  /// **'يتطلب المجلد المخصص إذن \"كل الملفات\" لأندرويد 11+'**
  String get setCustomFolderNeedsAllFiles;

  /// No description provided for @setConcurrency.
  ///
  /// In ar, this message translates to:
  /// **'التنزيلات المتزامنة'**
  String get setConcurrency;

  /// No description provided for @setWifiOnly.
  ///
  /// In ar, this message translates to:
  /// **'التنزيل عبر Wi-Fi فقط'**
  String get setWifiOnly;

  /// No description provided for @setNotifyDone.
  ///
  /// In ar, this message translates to:
  /// **'إشعار اكتمال التنزيل'**
  String get setNotifyDone;

  /// No description provided for @setNotifyError.
  ///
  /// In ar, this message translates to:
  /// **'إشعار أخطاء التنزيل'**
  String get setNotifyError;

  /// No description provided for @setNotifyStorage.
  ///
  /// In ar, this message translates to:
  /// **'تحذير المساحة'**
  String get setNotifyStorage;

  /// No description provided for @setThemeMode.
  ///
  /// In ar, this message translates to:
  /// **'الوضع'**
  String get setThemeMode;

  /// No description provided for @themeSystem.
  ///
  /// In ar, this message translates to:
  /// **'النظام'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In ar, this message translates to:
  /// **'فاتح'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ar, this message translates to:
  /// **'داكن'**
  String get themeDark;

  /// No description provided for @setDynamicColor.
  ///
  /// In ar, this message translates to:
  /// **'الألوان الديناميكية'**
  String get setDynamicColor;

  /// No description provided for @setDynamicColorDesc.
  ///
  /// In ar, this message translates to:
  /// **'استخراج ألوان النظام (Material You) على أندرويد 12+'**
  String get setDynamicColorDesc;

  /// No description provided for @setAnimations.
  ///
  /// In ar, this message translates to:
  /// **'الحركات'**
  String get setAnimations;

  /// No description provided for @setLayout.
  ///
  /// In ar, this message translates to:
  /// **'كثافة الواجهة'**
  String get setLayout;

  /// No description provided for @layoutCompact.
  ///
  /// In ar, this message translates to:
  /// **'مدمجة'**
  String get layoutCompact;

  /// No description provided for @layoutComfortable.
  ///
  /// In ar, this message translates to:
  /// **'مريحة'**
  String get layoutComfortable;

  /// No description provided for @setLanguage.
  ///
  /// In ar, this message translates to:
  /// **'اللغة'**
  String get setLanguage;

  /// No description provided for @langSystem.
  ///
  /// In ar, this message translates to:
  /// **'لغة النظام'**
  String get langSystem;

  /// No description provided for @langArabic.
  ///
  /// In ar, this message translates to:
  /// **'العربية'**
  String get langArabic;

  /// No description provided for @langEnglish.
  ///
  /// In ar, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @storageThumbnails.
  ///
  /// In ar, this message translates to:
  /// **'ذاكرة الصور المصغرة'**
  String get storageThumbnails;

  /// No description provided for @storageDownloadsSize.
  ///
  /// In ar, this message translates to:
  /// **'حجم التنزيلات'**
  String get storageDownloadsSize;

  /// No description provided for @storageClearCache.
  ///
  /// In ar, this message translates to:
  /// **'مسح ذاكرة التخزين المؤقت'**
  String get storageClearCache;

  /// No description provided for @storageCleared.
  ///
  /// In ar, this message translates to:
  /// **'تم المسح'**
  String get storageCleared;

  /// No description provided for @storageAnalyzer.
  ///
  /// In ar, this message translates to:
  /// **'محلل التخزين'**
  String get storageAnalyzer;

  /// No description provided for @storageLargestFiles.
  ///
  /// In ar, this message translates to:
  /// **'أكبر الملفات'**
  String get storageLargestFiles;

  /// No description provided for @storageOldestUnplayed.
  ///
  /// In ar, this message translates to:
  /// **'أقدم الملفات غير المشاهدة'**
  String get storageOldestUnplayed;

  /// No description provided for @privacyHistoryEnabled.
  ///
  /// In ar, this message translates to:
  /// **'تفعيل سجل المشاهدة'**
  String get privacyHistoryEnabled;

  /// No description provided for @privacyHistoryDesc.
  ///
  /// In ar, this message translates to:
  /// **'يُحفظ محليًا فقط ولا يُرسل لأي خادم'**
  String get privacyHistoryDesc;

  /// No description provided for @privacyClearHistory.
  ///
  /// In ar, this message translates to:
  /// **'مسح سجل المشاهدة'**
  String get privacyClearHistory;

  /// No description provided for @privacyClearSearch.
  ///
  /// In ar, this message translates to:
  /// **'مسح سجل البحث'**
  String get privacyClearSearch;

  /// No description provided for @privacyClearAllData.
  ///
  /// In ar, this message translates to:
  /// **'مسح جميع البيانات المحلية'**
  String get privacyClearAllData;

  /// No description provided for @privacyClearAllConfirm.
  ///
  /// In ar, this message translates to:
  /// **'سيُحذف السجل والمفضلات وقوائم التشغيل وإعدادات التنزيل. هل أنت متأكد؟'**
  String get privacyClearAllConfirm;

  /// No description provided for @privacyLocalDataNote.
  ///
  /// In ar, this message translates to:
  /// **'جميع البيانات (السجل، المفضلة، القوائم) محفوظة على جهازك فقط.'**
  String get privacyLocalDataNote;

  /// No description provided for @privacyPermissions.
  ///
  /// In ar, this message translates to:
  /// **'الأذونات'**
  String get privacyPermissions;

  /// No description provided for @privacyExportLogs.
  ///
  /// In ar, this message translates to:
  /// **'تصدير سجلات التشخيص'**
  String get privacyExportLogs;

  /// No description provided for @notifChannelDownloads.
  ///
  /// In ar, this message translates to:
  /// **'التنزيلات'**
  String get notifChannelDownloads;

  /// No description provided for @notifChannelGeneral.
  ///
  /// In ar, this message translates to:
  /// **'عام'**
  String get notifChannelGeneral;

  /// No description provided for @aboutVersion.
  ///
  /// In ar, this message translates to:
  /// **'الإصدار'**
  String get aboutVersion;

  /// No description provided for @aboutLicenses.
  ///
  /// In ar, this message translates to:
  /// **'تراخيص المصادر المفتوحة'**
  String get aboutLicenses;

  /// No description provided for @aboutPrivacyPolicy.
  ///
  /// In ar, this message translates to:
  /// **'سياسة الخصوصية'**
  String get aboutPrivacyPolicy;

  /// No description provided for @aboutPrivacyBody.
  ///
  /// In ar, this message translates to:
  /// **'لا يجمع DRS Video أي بيانات شخصية ولا يرسل سجل المشاهدة إلى أي خادم. كل شيء يبقى على جهازك. الاتصال بالإنترنت يقتصر على تشغيل وتنزيل المحتوى الذي تختاره أنت.'**
  String get aboutPrivacyBody;

  /// No description provided for @aboutDescription.
  ///
  /// In ar, this message translates to:
  /// **'مشغل فيديو ومنصة مكتبة متقدمة — بدون إعلانات وبدون ذكاء اصطناعي.'**
  String get aboutDescription;

  /// No description provided for @permNotificationTitle.
  ///
  /// In ar, this message translates to:
  /// **'إذن الإشعارات'**
  String get permNotificationTitle;

  /// No description provided for @permNotificationDesc.
  ///
  /// In ar, this message translates to:
  /// **'لإظهار تقدم التنزيلات واكتمالها.'**
  String get permNotificationDesc;

  /// No description provided for @permMediaTitle.
  ///
  /// In ar, this message translates to:
  /// **'إذن الوسائط'**
  String get permMediaTitle;

  /// No description provided for @permMediaDesc.
  ///
  /// In ar, this message translates to:
  /// **'لعرض ملفات الفيديو الموجودة على جهازك.'**
  String get permMediaDesc;

  /// No description provided for @permAllFilesTitle.
  ///
  /// In ar, this message translates to:
  /// **'إذن كل الملفات'**
  String get permAllFilesTitle;

  /// No description provided for @permAllFilesDesc.
  ///
  /// In ar, this message translates to:
  /// **'مطلوب فقط لحفظ التنزيلات في مجلد مخصص.'**
  String get permAllFilesDesc;

  /// No description provided for @permOpenSettings.
  ///
  /// In ar, this message translates to:
  /// **'فتح إعدادات النظام'**
  String get permOpenSettings;

  /// No description provided for @ob1Title.
  ///
  /// In ar, this message translates to:
  /// **'كل فيديوهاتك في مكان واحد'**
  String get ob1Title;

  /// No description provided for @ob1Body.
  ///
  /// In ar, this message translates to:
  /// **'المكتبة والمفضلة وقوائم التشغيل وسجل المشاهدة — منظمة محليًا على جهازك.'**
  String get ob1Body;

  /// No description provided for @ob2Title.
  ///
  /// In ar, this message translates to:
  /// **'مشغل احترافي'**
  String get ob2Title;

  /// No description provided for @ob2Body.
  ///
  /// In ar, this message translates to:
  /// **'سرعات، ترجمات، مسارات صوتية، قفل، نافذة عائمة، وتحكم بالإيماءات.'**
  String get ob2Body;

  /// No description provided for @ob3Title.
  ///
  /// In ar, this message translates to:
  /// **'تنزيل حقيقي في الخلفية'**
  String get ob3Title;

  /// No description provided for @ob3Body.
  ///
  /// In ar, this message translates to:
  /// **'إيقاف مؤقت واستئناف وإدارة أولويات — من المصادر التي تسمح بذلك.'**
  String get ob3Body;

  /// No description provided for @obGetStarted.
  ///
  /// In ar, this message translates to:
  /// **'لنبدأ'**
  String get obGetStarted;

  /// No description provided for @obSkip.
  ///
  /// In ar, this message translates to:
  /// **'تخطي'**
  String get obSkip;

  /// No description provided for @openUrlTitle.
  ///
  /// In ar, this message translates to:
  /// **'فتح رابط فيديو'**
  String get openUrlTitle;

  /// No description provided for @openUrlHint.
  ///
  /// In ar, this message translates to:
  /// **'https://example.com/video.mp4'**
  String get openUrlHint;

  /// No description provided for @openUrlInvalid.
  ///
  /// In ar, this message translates to:
  /// **'رابط غير صالح — يجب أن يبدأ بـ http/https'**
  String get openUrlInvalid;

  /// No description provided for @pickSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'اختر ملف ترجمة (SRT / VTT)'**
  String get pickSubtitle;

  /// No description provided for @renameTitle.
  ///
  /// In ar, this message translates to:
  /// **'إعادة تسمية'**
  String get renameTitle;

  /// No description provided for @reasonFavorite.
  ///
  /// In ar, this message translates to:
  /// **'من مفضلاتك'**
  String get reasonFavorite;

  /// No description provided for @reasonRecentlyPlayed.
  ///
  /// In ar, this message translates to:
  /// **'شاهدته مؤخرًا'**
  String get reasonRecentlyPlayed;

  /// No description provided for @reasonUnfinished.
  ///
  /// In ar, this message translates to:
  /// **'لم تكمله'**
  String get reasonUnfinished;

  /// No description provided for @reasonFromSource.
  ///
  /// In ar, this message translates to:
  /// **'من {source}'**
  String reasonFromSource(String source);

  /// No description provided for @reasonSimilarSource.
  ///
  /// In ar, this message translates to:
  /// **'مصادر تحبها'**
  String get reasonSimilarSource;

  /// No description provided for @updateThumb.
  ///
  /// In ar, this message translates to:
  /// **'تحديث'**
  String get updateThumb;

  /// No description provided for @scanComplete.
  ///
  /// In ar, this message translates to:
  /// **'اكتمل الفحص'**
  String get scanComplete;

  /// No description provided for @waiting.
  ///
  /// In ar, this message translates to:
  /// **'بالانتظار…'**
  String get waiting;

  /// Boot screen: services are initializing
  ///
  /// In ar, this message translates to:
  /// **'جارٍ تجهيز التطبيق…'**
  String get bootPreparing;

  /// No description provided for @bootStageCore.
  ///
  /// In ar, this message translates to:
  /// **'تحضير الأساسيات'**
  String get bootStageCore;

  /// No description provided for @bootStagePrefs.
  ///
  /// In ar, this message translates to:
  /// **'تحميل الإعدادات'**
  String get bootStagePrefs;

  /// No description provided for @bootStageDatabase.
  ///
  /// In ar, this message translates to:
  /// **'تهيئة قاعدة البيانات'**
  String get bootStageDatabase;

  /// No description provided for @bootStageRepositories.
  ///
  /// In ar, this message translates to:
  /// **'تحميل المكتبة والسجل'**
  String get bootStageRepositories;

  /// No description provided for @bootStageNotifications.
  ///
  /// In ar, this message translates to:
  /// **'تهيئة الإشعارات'**
  String get bootStageNotifications;

  /// No description provided for @bootStagePlayer.
  ///
  /// In ar, this message translates to:
  /// **'تجهيز محرك التشغيل'**
  String get bootStagePlayer;

  /// No description provided for @bootStageDownloads.
  ///
  /// In ar, this message translates to:
  /// **'تجهيز مدير التحميلات'**
  String get bootStageDownloads;

  /// No description provided for @bootStageSources.
  ///
  /// In ar, this message translates to:
  /// **'تحميل المصادر'**
  String get bootStageSources;

  /// No description provided for @bootSlow.
  ///
  /// In ar, this message translates to:
  /// **'التجهيز يستغرق وقتًا أطول من المعتاد. يمكنك إعادة المحاولة أو المتابعة بالانتظار.'**
  String get bootSlow;

  /// No description provided for @bootRetry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get bootRetry;

  /// No description provided for @bootSafeMode.
  ///
  /// In ar, this message translates to:
  /// **'الوضع الآمن'**
  String get bootSafeMode;

  /// No description provided for @bootErrorTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تشغيل التطبيق'**
  String get bootErrorTitle;

  /// No description provided for @bootErrorBody.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ أثناء تهيئة التطبيق. أعد المحاولة، أو ابدأ بالوضع الآمن الذي يبدأ التطبيق بأقل قدر من الميزات.'**
  String get bootErrorBody;

  /// No description provided for @bootErrorDetails.
  ///
  /// In ar, this message translates to:
  /// **'التفاصيل التقنية'**
  String get bootErrorDetails;

  /// No description provided for @bootErrorCopy.
  ///
  /// In ar, this message translates to:
  /// **'نسخ التفاصيل'**
  String get bootErrorCopy;

  /// No description provided for @bootErrorCopied.
  ///
  /// In ar, this message translates to:
  /// **'تم نسخ التفاصيل إلى الحافظة'**
  String get bootErrorCopied;

  /// No description provided for @bootPrevCrashTitle.
  ///
  /// In ar, this message translates to:
  /// **'تم رصد مشكلة في الجلسة السابقة'**
  String get bootPrevCrashTitle;

  /// No description provided for @bootPrevCrashBody.
  ///
  /// In ar, this message translates to:
  /// **'لم يُغلق التطبيق بشكل سليم في المرة الأخيرة. يمكنك نسخ التفاصيل أدناه وإرسالها إلينا لمعرفة السبب.'**
  String get bootPrevCrashBody;

  /// No description provided for @bootPrevCrashDetails.
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل العطل'**
  String get bootPrevCrashDetails;

  /// No description provided for @setDiagnostics.
  ///
  /// In ar, this message translates to:
  /// **'التشخيص والأخطاء'**
  String get setDiagnostics;

  /// No description provided for @diagDeviceSection.
  ///
  /// In ar, this message translates to:
  /// **'معلومات الجهاز'**
  String get diagDeviceSection;

  /// No description provided for @diagFactsApp.
  ///
  /// In ar, this message translates to:
  /// **'التطبيق'**
  String get diagFactsApp;

  /// No description provided for @diagFactsDevice.
  ///
  /// In ar, this message translates to:
  /// **'الجهاز'**
  String get diagFactsDevice;

  /// No description provided for @diagFactsAndroid.
  ///
  /// In ar, this message translates to:
  /// **'أندرويد'**
  String get diagFactsAndroid;

  /// No description provided for @diagFactsAbi.
  ///
  /// In ar, this message translates to:
  /// **'المعمارية'**
  String get diagFactsAbi;

  /// No description provided for @diagFactsStorage.
  ///
  /// In ar, this message translates to:
  /// **'مساحة التخزين'**
  String get diagFactsStorage;

  /// No description provided for @diagChecksSection.
  ///
  /// In ar, this message translates to:
  /// **'فحوصات الخدمات'**
  String get diagChecksSection;

  /// No description provided for @diagRunChecks.
  ///
  /// In ar, this message translates to:
  /// **'فحص الآن'**
  String get diagRunChecks;

  /// No description provided for @diagStatusPass.
  ///
  /// In ar, this message translates to:
  /// **'سليم'**
  String get diagStatusPass;

  /// No description provided for @diagStatusDegraded.
  ///
  /// In ar, this message translates to:
  /// **'محدود'**
  String get diagStatusDegraded;

  /// No description provided for @diagStatusFail.
  ///
  /// In ar, this message translates to:
  /// **'فاشل'**
  String get diagStatusFail;

  /// No description provided for @diagCheckPrefs.
  ///
  /// In ar, this message translates to:
  /// **'التفضيلات المحفوظة'**
  String get diagCheckPrefs;

  /// No description provided for @diagCheckDatabase.
  ///
  /// In ar, this message translates to:
  /// **'قاعدة البيانات'**
  String get diagCheckDatabase;

  /// No description provided for @diagCheckStorage.
  ///
  /// In ar, this message translates to:
  /// **'التخزين الداخلي'**
  String get diagCheckStorage;

  /// No description provided for @diagCheckPlayer.
  ///
  /// In ar, this message translates to:
  /// **'محرك التشغيل (mpv)'**
  String get diagCheckPlayer;

  /// No description provided for @diagCheckDownloader.
  ///
  /// In ar, this message translates to:
  /// **'محرك التحميلات'**
  String get diagCheckDownloader;

  /// No description provided for @diagCheckNotifications.
  ///
  /// In ar, this message translates to:
  /// **'الإشعارات'**
  String get diagCheckNotifications;

  /// No description provided for @diagCheckNative.
  ///
  /// In ar, this message translates to:
  /// **'جسر النظام (Native)'**
  String get diagCheckNative;

  /// No description provided for @diagCheckCache.
  ///
  /// In ar, this message translates to:
  /// **'الذاكرة المؤقتة'**
  String get diagCheckCache;

  /// No description provided for @diagCheckCrashes.
  ///
  /// In ar, this message translates to:
  /// **'سجل الأعطال'**
  String get diagCheckCrashes;

  /// No description provided for @diagCrashesSection.
  ///
  /// In ar, this message translates to:
  /// **'الأعطال المُسجلة'**
  String get diagCrashesSection;

  /// No description provided for @diagNoCrashes.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد أعطال مُسجلة من الجلسات السابقة.'**
  String get diagNoCrashes;

  /// No description provided for @diagPrevCrashDetails.
  ///
  /// In ar, this message translates to:
  /// **'عرض تفاصيل العطل'**
  String get diagPrevCrashDetails;

  /// No description provided for @diagClearLogs.
  ///
  /// In ar, this message translates to:
  /// **'مسح السجلات'**
  String get diagClearLogs;

  /// No description provided for @diagLogsCleared.
  ///
  /// In ar, this message translates to:
  /// **'تم مسح سجلات الأعطال'**
  String get diagLogsCleared;

  /// No description provided for @diagSessionLog.
  ///
  /// In ar, this message translates to:
  /// **'سجل الجلسة الحالية'**
  String get diagSessionLog;

  /// No description provided for @diagSessionLogBody.
  ///
  /// In ar, this message translates to:
  /// **'آخر 120 حدثًا مسجلاً خلال هذه الجلسة'**
  String get diagSessionLogBody;

  /// No description provided for @diagCopyReport.
  ///
  /// In ar, this message translates to:
  /// **'نسخ'**
  String get diagCopyReport;

  /// No description provided for @diagReportCopied.
  ///
  /// In ar, this message translates to:
  /// **'تم النسخ إلى الحافظة'**
  String get diagReportCopied;

  /// No description provided for @diagShareReport.
  ///
  /// In ar, this message translates to:
  /// **'مشاركة التقرير الكامل'**
  String get diagShareReport;

  /// No description provided for @diagLocalNote.
  ///
  /// In ar, this message translates to:
  /// **'كل شيء يبقى على جهازك ولا يُرسل أي بيان إلا إذا شاركت التقرير بنفسك.'**
  String get diagLocalNote;

  /// No description provided for @dlDegradedTitle.
  ///
  /// In ar, this message translates to:
  /// **'محرك التحميلات غير متاح حاليًا'**
  String get dlDegradedTitle;

  /// No description provided for @dlDegradedRetry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة تهيئة محرك التحميلات'**
  String get dlDegradedRetry;

  /// No description provided for @bootSafeModePreparing.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ التشغيل بالوضع الآمن…'**
  String get bootSafeModePreparing;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
