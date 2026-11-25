import 'package:flutter/widgets.dart';

/// كل نصوص التطبيق بالعربية والإنجليزية.
/// الاستخدام: AppStrings.of('ar').channels
class AppStrings {
  final String code;
  const AppStrings._(this.code);

  static const AppStrings ar = AppStrings._('ar');
  static const AppStrings en = AppStrings._('en');

  static const List<String> supportedCodes = ['ar', 'en'];

  static AppStrings of(String code) => code == 'ar' ? ar : en;

  /// يحدد لغة العرض: preference = system | ar | en
  static String resolveCode(String preference, String deviceCode) {
    if (preference == 'ar' || preference == 'en') return preference;
    return supportedCodes.contains(deviceCode) ? deviceCode : 'en';
  }

  bool get isAr => code == 'ar';
  Locale get locale => Locale(code);
  TextDirection get direction => isAr ? TextDirection.rtl : TextDirection.ltr;

  String _t(String a, String e) => isAr ? a : e;

  // ───────── عام ─────────
  String get appName => _t('لُمورا', 'Lumora');
  String get tagline => _t('شاهد بوضوح. بلا حدود.', 'Watch clearly. Without limits.');
  String get ok => _t('حسناً', 'OK');
  String get cancel => _t('إلغاء', 'Cancel');
  String get save => _t('حفظ', 'Save');
  String get delete => _t('حذف', 'Delete');
  String get add => _t('إضافة', 'Add');
  String get edit => _t('تعديل', 'Edit');
  String get close => _t('إغلاق', 'Close');
  String get retry => _t('إعادة المحاولة', 'Retry');
  String get search => _t('بحث', 'Search');
  String get loading => _t('جارٍ التحميل...', 'Loading...');
  String get done => _t('تم', 'Done');
  String get confirm => _t('تأكيد', 'Confirm');
  String get yes => _t('نعم', 'Yes');
  String get no => _t('لا', 'No');
  String get unknownError => _t('حدث خطأ غير متوقع', 'Something went wrong');
  String get noInternet => _t('لا يوجد اتصال بالإنترنت', 'No internet connection');

  // ───────── التنقل ─────────
  String get navChannels => _t('القنوات', 'Channels');
  String get navFavorites => _t('المفضلة', 'Favorites');
  String get navPlaylists => _t('القوائم', 'Playlists');
  String get navSettings => _t('الإعدادات', 'Settings');

  // ───────── القنوات ─────────
  String get allChannels => _t('الكل', 'All');
  String get recent => _t('الأخيرة', 'Recent');
  String get categories => _t('التصنيفات', 'Categories');
  String get uncategorized => _t('بدون تصنيف', 'Uncategorized');
  String get searchChannelsHint => _t('ابحث عن قناة...', 'Search channels...');
  String get noChannels => _t('لا توجد قنوات', 'No channels');
  String get noChannelsHint =>
      _t('أضف قائمة تشغيل لتظهر القنوات هنا', 'Add a playlist to see channels here');
  String get noResults => _t('لا توجد نتائج', 'No results');
  String get live => _t('مباشر', 'LIVE');
  String get addToFavorites => _t('إضافة للمفضلة', 'Add to favorites');
  String get removeFromFavorites => _t('إزالة من المفضلة', 'Remove from favorites');
  String get hideChannel => _t('إخفاء القناة', 'Hide channel');
  String get hiddenChannels => _t('القنوات المخفية', 'Hidden channels');
  String get unhide => _t('إظهار', 'Unhide');
  String get noFavorites => _t('لا توجد مفضلة بعد', 'No favorites yet');
  String get noFavoritesHint =>
      _t('اضغط على القلب في أي قناة لإضافتها هنا', 'Tap the heart on any channel to add it here');
  String get lockedCategory => _t('تصنيف مقفل', 'Locked category');

  String channelsCount(int n) {
    if (isAr) {
      if (n == 0) return 'لا قنوات';
      if (n == 1) return 'قناة واحدة';
      if (n == 2) return 'قناتان';
      if (n >= 3 && n <= 10) return '$n قنوات';
      return '$n قناة';
    }
    return n == 1 ? '1 channel' : '$n channels';
  }

  // ───────── قوائم التشغيل ─────────
  String get addPlaylist => _t('إضافة قائمة', 'Add playlist');
  String get fromUrl => _t('من رابط', 'From URL');
  String get fromFile => _t('من ملف', 'From file');
  String get xtreamCodes => _t('Xtream Codes', 'Xtream Codes');
  String get playlistName => _t('اسم القائمة', 'Playlist name');
  String get playlistUrl => _t('رابط القائمة (M3U / M3U8)', 'Playlist URL (M3U / M3U8)');
  String get serverUrl => _t('عنوان الخادم', 'Server URL');
  String get username => _t('اسم المستخدم', 'Username');
  String get password => _t('كلمة المرور', 'Password');
  String get epgUrl => _t('رابط الدليل (EPG) اختياري', 'EPG URL (optional)');
  String get pickFile => _t('اختيار ملف', 'Choose file');
  String get noPlaylists => _t('لا توجد قوائم', 'No playlists');
  String get noPlaylistsHint =>
      _t('أضف قائمتك الأولى للبدء', 'Add your first playlist to get started');
  String get refresh => _t('تحديث', 'Refresh');
  String get refreshAll => _t('تحديث الكل', 'Refresh all');
  String get lastUpdated => _t('آخر تحديث', 'Last updated');
  String get never => _t('لم تُحدَّث بعد', 'Never updated');
  String get importing => _t('جارٍ استيراد القنوات...', 'Importing channels...');
  String get playlistAdded => _t('تمت إضافة القائمة', 'Playlist added');
  String get playlistUpdated => _t('تم تحديث القائمة', 'Playlist updated');
  String get playlistDeleted => _t('تم حذف القائمة', 'Playlist deleted');
  String get invalidPlaylist =>
      _t('القائمة غير صالحة أو فارغة', 'The playlist is invalid or empty');
  String get invalidUrl => _t('الرابط غير صالح', 'Invalid URL');
  String get fieldRequired => _t('هذا الحقل مطلوب', 'This field is required');
  String get loginFailed =>
      _t('فشل تسجيل الدخول، تحقق من البيانات', 'Login failed, check your details');
  String get connectionTimeout =>
      _t('انتهت مهلة الاتصال بالخادم', 'The connection to the server timed out');
  String get serverUnreachable => _t(
        'تعذّر الوصول إلى الخادم، تحقق من العنوان والمنفذ',
        'Cannot reach the server, check the address and port',
      );
  String get serverError => _t(
        'الخادم رفض الطلب أو أعاد استجابة غير صالحة',
        'The server rejected the request or sent an invalid response',
      );
  String get deletePlaylistTitle => _t('حذف القائمة؟', 'Delete playlist?');
  String get deletePlaylistBody =>
      _t('ستُحذف القائمة وكل قنواتها من الجهاز.', 'The playlist and its channels will be removed from this device.');
  String get disclaimer => _t(
        'لُمورا مشغّل فقط ولا يتضمن أي قنوات أو محتوى. المحتوى من مصادرك أنت.',
        'Lumora is a player only and includes no channels or content. Content comes from your own sources.',
      );

  // ───────── المشغّل ─────────
  String get buffering => _t('جارٍ التحميل...', 'Buffering...');
  String get reconnecting => _t('إعادة الاتصال...', 'Reconnecting...');
  String get playbackError => _t('تعذّر تشغيل القناة', 'Unable to play this channel');
  String get nextChannel => _t('القناة التالية', 'Next channel');
  String get previousChannel => _t('القناة السابقة', 'Previous channel');
  String get aspectRatio => _t('أبعاد الشاشة', 'Aspect ratio');
  String get fit => _t('ملاءمة', 'Fit');
  String get fill => _t('ملء', 'Fill');
  String get stretch => _t('تمديد', 'Stretch');
  String get pip => _t('صورة داخل صورة', 'Picture in picture');
  String get brightness => _t('السطوع', 'Brightness');
  String get volume => _t('الصوت', 'Volume');
  String get lockControls => _t('قفل الأزرار', 'Lock controls');
  String get unlockControls => _t('إلغاء القفل', 'Unlock');
  String get channelList => _t('قائمة القنوات', 'Channel list');
  String get nowPlaying => _t('يُعرض الآن', 'Now playing');
  String get upNext => _t('التالي', 'Up next');
  String get noGuide => _t('لا يوجد دليل برامج', 'No program guide');

  // ───────── الإعدادات ─────────
  String get language => _t('اللغة', 'Language');
  String get languageSystem => _t('لغة الجهاز', 'Device language');
  String get languageArabic => 'العربية';
  String get languageEnglish => 'English';
  String get appearance => _t('المظهر', 'Appearance');
  String get themeSystem => _t('حسب الجهاز', 'System');
  String get themeDark => _t('داكن', 'Dark');
  String get themeLight => _t('فاتح', 'Light');
  String get playback => _t('التشغيل', 'Playback');
  String get bufferSize => _t('حجم التخزين المؤقت', 'Buffer size');
  String get bufferSmall => _t('صغير (أسرع بدء)', 'Small (faster start)');
  String get bufferMedium => _t('متوسط (متوازن)', 'Medium (balanced)');
  String get bufferLarge => _t('كبير (أثبت)', 'Large (more stable)');
  String get hardwareDecoding => _t('فك الترميز بالعتاد', 'Hardware decoding');
  String get autoReconnect => _t('إعادة الاتصال تلقائياً', 'Auto reconnect');
  String get keepScreenOn => _t('إبقاء الشاشة مضاءة', 'Keep screen on');
  String get parentalControl => _t('التحكم الأبوي', 'Parental control');
  String get setPin => _t('تعيين رمز PIN', 'Set PIN');
  String get changePin => _t('تغيير رمز PIN', 'Change PIN');
  String get removePin => _t('إزالة رمز PIN', 'Remove PIN');
  String get enterPin => _t('أدخل رمز PIN', 'Enter PIN');
  String get confirmPin => _t('أعد إدخال الرمز', 'Confirm PIN');
  String get wrongPin => _t('الرمز غير صحيح', 'Incorrect PIN');
  String get pinMismatch => _t('الرمزان غير متطابقين', 'PINs do not match');
  String get pinLength => _t('الرمز من 4 أرقام', 'PIN must be 4 digits');
  String get lockedCategories => _t('التصنيفات المقفلة', 'Locked categories');
  String get storage => _t('التخزين', 'Storage');
  String get clearCache => _t('مسح الذاكرة المؤقتة', 'Clear cache');
  String get cacheCleared => _t('تم مسح الذاكرة المؤقتة', 'Cache cleared');
  String get about => _t('حول التطبيق', 'About');
  String get version => _t('الإصدار', 'Version');
}
