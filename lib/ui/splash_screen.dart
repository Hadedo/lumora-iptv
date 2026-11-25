import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../providers/app_providers.dart';

/// شعار لُمورا: دائرة متوهجة بحلقة متدرجة، وبداخلها مثلث تشغيل بحواف ناعمة.
/// ويُستخدم أيضاً في الحالات الفارغة وشاشة "حول التطبيق".
class LumoraLogo extends StatelessWidget {
  final double size;
  final bool glow;

  const LumoraLogo({super.key, this.size = 96, this.glow = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(glow: glow)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final bool glow;
  const _LogoPainter({required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ringR = r * 0.80;
    final rect = Rect.fromCircle(center: c, radius: ringR);

    // الهالة
    if (glow) {
      canvas.drawCircle(
        c,
        ringR,
        Paint()
          ..color = AppColors.primary.withOpacity(0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.35),
      );
    }

    // القرص الداخلي
    canvas.drawCircle(c, ringR, Paint()..color = const Color(0xFF0F1220));

    // الحلقة المتدرجة
    canvas.drawCircle(
      c,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.085
        ..shader = const SweepGradient(
          colors: [AppColors.primary, AppColors.secondary, AppColors.primary],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );

    // مثلث التشغيل
    final t = r * 0.36;
    final cx = c.dx + t * 0.12;
    final path = Path()
      ..moveTo(cx - t * 0.55, c.dy - t)
      ..lineTo(cx + t * 0.95, c.dy)
      ..lineTo(cx - t * 0.55, c.dy + t)
      ..close();

    final shader = AppColors.brandGradient.createShader(path.getBounds());
    canvas.drawPath(path, Paint()..shader = shader);
    // حدّ بنفس اللون بزوايا مستديرة يعطي حواف ناعمة.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.09
        ..strokeJoin = StrokeJoin.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.glow != glow;
}

/// شاشة البداية: ظهور الشعار ثم الاسم ثم الشعار النصي، وبعدها تستدعي onDone.
/// الانتقال للشاشة الرئيسية يتم من main.dart، فلا تعتمد هذه الشاشة على ملفات أخرى.
class SplashScreen extends ConsumerStatefulWidget {
  final VoidCallback onDone;

  const SplashScreen({super.key, required this.onDone});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _nameFade;
  late final Animation<Offset> _nameSlide;
  late final Animation<double> _tagFade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
    ));
    _logoFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _nameFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
    );
    _nameSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _c,
      curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
    ));
    _tagFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.55, 0.9, curve: Curves.easeOut),
    );

    _c.forward().whenComplete(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final bg = AppColors.dark.background;

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.35),
            radius: 1.0,
            colors: [AppColors.primary.withOpacity(0.22), bg],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 5),
              FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: const LumoraLogo(size: 132),
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: _nameFade,
                child: SlideTransition(
                  position: _nameSlide,
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (rect) =>
                        AppColors.brandGradient.createShader(rect),
                    child: Text(
                      s.appName,
                      style: TextStyle(
                        fontSize: 40,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                        // التباعد بين الأحرف يفكك اتصال الحروف العربية.
                        letterSpacing: s.isAr ? 0 : 3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FadeTransition(
                opacity: _tagFade,
                child: Text(
                  s.tagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.dark.textSecondary,
                  ),
                ),
              ),
              const Spacer(flex: 4),
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) => SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _c.value,
                      minHeight: 3,
                      backgroundColor: AppColors.dark.border,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.secondary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
