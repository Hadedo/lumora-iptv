import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/l10n/strings.dart';
import 'core/theme/app_theme.dart';
import 'data/services/storage_service.dart';
import 'providers/app_providers.dart';
import 'ui/home_shell.dart';
import 'ui/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ضروري قبل أي استخدام للمشغّل.
  MediaKit.ensureInitialized();

  // واجهة بملء الشاشة بشريطي نظام شفافين.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final storage = await StorageService.init();

  runApp(
    ProviderScope(
      overrides: [storageProvider.overrideWithValue(storage)],
      child: const LumoraApp(),
    ),
  );
}

class LumoraApp extends ConsumerStatefulWidget {
  const LumoraApp({super.key});

  @override
  ConsumerState<LumoraApp> createState() => _LumoraAppState();
}

class _LumoraAppState extends ConsumerState<LumoraApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// عند تغيّر لغة الجهاز أثناء التشغيل نحدّث لغة التطبيق إن كانت "لغة الجهاز".
  @override
  void didChangeLocales(List<Locale>? locales) {
    final code = (locales != null && locales.isNotEmpty)
        ? locales.first.languageCode
        : WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    ref.read(deviceLanguageProvider.notifier).state = code;
  }

  @override
  Widget build(BuildContext context) {
    final code = ref.watch(languageCodeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final s = ref.watch(stringsProvider);

    return MaterialApp(
      title: s.appName,
      debugShowCheckedModeBanner: false,
      locale: Locale(code),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(code),
      darkTheme: AppTheme.dark(code),
      themeMode: themeMode,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _Root(),
    );
  }
}

/// الجذر: شاشة البداية ثم الهيكل الرئيسي بانتقال ناعم.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOut,
      child: _splashDone
          ? const HomeShell(key: ValueKey('home'))
          : SplashScreen(
              key: const ValueKey('splash'),
              onDone: () {
                if (mounted) setState(() => _splashDone = true);
              },
            ),
    );
  }
}
