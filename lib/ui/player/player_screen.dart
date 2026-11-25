import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../data/models/channel.dart';
import '../../providers/app_providers.dart';
import '../widgets/channel_tile.dart';

enum _Status { loading, playing, buffering, reconnecting, error }

enum _GestureKind { brightness, volume }

/// مشغّل لُمورا: بث مباشر مع إعادة اتصال ذكية، إيماءات للسطوع والصوت،
/// تدوير تلقائي، وتبديل سريع بين القنوات.
class PlayerScreen extends ConsumerStatefulWidget {
  final Channel channel;
  final List<Channel> queue;

  const PlayerScreen({
    super.key,
    required this.channel,
    required this.queue,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _video;
  late final Future<void> _ready;

  late Channel _channel;
  late List<Channel> _queue;
  late AspectMode _aspect;

  final List<StreamSubscription<dynamic>> _subs = [];

  _Status _status = _Status.loading;
  int _attempt = 0;
  int _session = 0;
  bool _retryPending = false;

  Timer? _reconnectTimer;
  Timer? _bufferTimer;
  Timer? _stableTimer;
  Timer? _hideTimer;
  Timer? _gestureTimer;

  bool _controlsVisible = true;
  bool _locked = false;
  bool _fullscreen = false;
  bool? _lastLandscape;

  double _brightness = 0.5;
  double _volume = 0.5;
  bool _dragLeft = true;
  _GestureKind? _gesture;
  double _gestureValue = 0;

  @override
  void initState() {
    super.initState();
    final st = ref.read(settingsProvider);

    _aspect = st.aspect;
    _channel = widget.channel;
    _queue = widget.queue.isEmpty ? [widget.channel] : widget.queue;
    if (!_queue.any((c) => c.id == _channel.id)) {
      _queue = [_channel, ..._queue];
    }

    _player = Player(
      configuration: PlayerConfiguration(bufferSize: st.buffer.bytes),
    );
    _video = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: st.hardwareDecoding,
      ),
    );

    _ready = _tuneEngine(st);
    _listen();
    _initLevels();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _open();
    _scheduleHide();
  }

  @override
  void dispose() {
    _session++;
    _reconnectTimer?.cancel();
    _bufferTimer?.cancel();
    _stableTimer?.cancel();
    _hideTimer?.cancel();
    _gestureTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ScreenBrightness().resetScreenBrightness().catchError((_) {});
    super.dispose();
  }

  // ═════════════ المحرك ═════════════

  /// إعدادات mpv: حجم التخزين المسبق وإعادة الاتصال على مستوى الشبكة.
  Future<void> _tuneEngine(SettingsState st) async {
    try {
      final p = _player.platform as dynamic;
      await p.setProperty('cache-secs', '${st.buffer.seconds}');
      await p.setProperty('demuxer-readahead-secs', '${st.buffer.seconds}');
      await p.setProperty('network-timeout', '15');
      if (st.autoReconnect) {
        await p.setProperty(
          'stream-lavf-o',
          'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',
        );
      }
    } catch (_) {
      // الإعدادات اختيارية، والتشغيل يعمل بدونها.
    }
  }

  void _listen() {
    _subs.add(_player.stream.playing.listen((p) {
      if (!mounted) return;
      if (p && !_player.state.buffering && !_retryPending) _markPlaying();
      setState(() {});
      _scheduleHide();
    }));
    _subs.add(_player.stream.buffering.listen(_onBuffering));
    _subs.add(_player.stream.error.listen((_) => _scheduleReconnect()));
    _subs.add(_player.stream.completed.listen((done) {
      if (done) _scheduleReconnect();
    }));
  }

  Future<void> _open() async {
    if (!mounted) return;
    _retryPending = false;
    final session = ++_session;
    _bufferTimer?.cancel();

    setState(() {
      _status = _attempt == 0 ? _Status.loading : _Status.reconnecting;
    });

    try {
      await _ready;
      if (!mounted || session != _session) return;
      await _player.open(
        Media(
          _channel.url,
          httpHeaders: _channel.headers(AppConstants.streamUserAgent),
        ),
      );
    } catch (_) {
      if (mounted && session == _session) _scheduleReconnect();
      return;
    }
    if (!mounted || session != _session) return;

    // إن لم يبدأ البث خلال المهلة نعيد المحاولة.
    _bufferTimer = Timer(AppConstants.bufferingTimeout, () {
      if (mounted && session == _session && _status != _Status.playing) {
        _scheduleReconnect();
      }
    });
  }

  void _markPlaying() {
    _bufferTimer?.cancel();
    _stableTimer?.cancel();
    // نصفّر عدّاد المحاولات فقط بعد استقرار البث 8 ثوانٍ.
    _stableTimer = Timer(const Duration(seconds: 8), () => _attempt = 0);
    if (_status != _Status.playing && mounted) {
      setState(() => _status = _Status.playing);
    }
  }

  void _onBuffering(bool buffering) {
    if (!mounted) return;
    if (buffering) {
      if (_status == _Status.playing) {
        setState(() => _status = _Status.buffering);
      }
      _bufferTimer?.cancel();
      _bufferTimer = Timer(AppConstants.bufferingTimeout, () {
        if (mounted && _player.state.buffering) _scheduleReconnect();
      });
    } else if (_player.state.playing && !_retryPending) {
      _markPlaying();
    }
  }

  /// إعادة اتصال بتأخير متصاعد (2، 4، 8، 15 ثانية...) حتى حدّ أقصى.
  void _scheduleReconnect() {
    if (!mounted || _retryPending) return;
    _bufferTimer?.cancel();
    _stableTimer?.cancel();

    final auto = ref.read(settingsProvider).autoReconnect;
    if (!auto || _attempt >= AppConstants.maxReconnectAttempts) {
      setState(() => _status = _Status.error);
      return;
    }

    _attempt++;
    _retryPending = true;
    setState(() => _status = _Status.reconnecting);

    final ms = math.min(
      AppConstants.reconnectBaseDelay.inMilliseconds * (1 << (_attempt - 1)),
      AppConstants.reconnectMaxDelay.inMilliseconds,
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: ms), _open);
  }

  void _retryNow() {
    _reconnectTimer?.cancel();
    _attempt = 0;
    _open();
  }

  // ═════════════ القنوات ═════════════

  int get _index => math.max(0, _queue.indexWhere((c) => c.id == _channel.id));

  void _switchTo(int index) {
    final n = _queue.length;
    final c = _queue[((index % n) + n) % n];
    if (c.id == _channel.id) return;

    _reconnectTimer?.cancel();
    _retryPending = false;
    _attempt = 0;
    setState(() => _channel = c);
    ref.read(recentsProvider.notifier).add(c);
    _open();
    _showControls();
  }

  void _next() => _switchTo(_index + 1);
  void _previous() => _switchTo(_index - 1);

  // ═════════════ التحكم والواجهة ═════════════

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_controlsVisible || !_player.state.playing) return;
    _hideTimer = Timer(AppConstants.controlsAutoHide, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _cycleAspect() {
    setState(() => _aspect = _aspect.next);
    ref.read(settingsProvider.notifier).setAspect(_aspect);
    _scheduleHide();
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    HapticFeedback.mediumImpact();
    _scheduleHide();
  }

  BoxFit get _fit {
    switch (_aspect) {
      case AspectMode.fit:
        return BoxFit.contain;
      case AspectMode.fill:
        return BoxFit.cover;
      case AspectMode.stretch:
        return BoxFit.fill;
    }
  }

  String _aspectLabel(AppStrings s) {
    switch (_aspect) {
      case AspectMode.fit:
        return s.fit;
      case AspectMode.fill:
        return s.fill;
      case AspectMode.stretch:
        return s.stretch;
    }
  }

  // ═════════════ الدوران ═════════════

  void _applyUiMode(bool landscape) {
    if (_lastLandscape == landscape) return;
    _lastLandscape = landscape;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(
        landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    });
  }

  Future<void> _toggleFullscreen() async {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (landscape) {
      await _exitFullscreen();
    } else {
      setState(() => _fullscreen = true);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _scheduleHide();
  }

  Future<void> _exitFullscreen() async {
    if (mounted) setState(() => _fullscreen = false);
    await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp],
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void _onBack() {
    if (_fullscreen) {
      _exitFullscreen();
    } else {
      Navigator.of(context).pop();
    }
  }

  // ═════════════ السطوع والصوت ═════════════

  Future<void> _initLevels() async {
    try {
      _brightness = await ScreenBrightness().current;
    } catch (_) {}
    try {
      _volume = await VolumeController().getVolume();
    } catch (_) {}
  }

  double _c01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  void _onDrag(DragUpdateDetails d, double height) {
    final delta = -d.delta.dy / height * AppConstants.gestureSensitivity;
    if (_dragLeft) {
      _brightness = _c01(_brightness + delta);
      ScreenBrightness().setScreenBrightness(_brightness).catchError((_) {});
      _flash(_GestureKind.brightness, _brightness);
    } else {
      _volume = _c01(_volume + delta);
      try {
        VolumeController().setVolume(_volume);
      } catch (_) {}
      _flash(_GestureKind.volume, _volume);
    }
  }

  void _flash(_GestureKind kind, double value) {
    _gestureTimer?.cancel();
    setState(() {
      _gesture = kind;
      _gestureValue = value;
    });
    _gestureTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _gesture = null);
    });
  }

  // ═════════════ القائمة ═════════════

  void _openQueueSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        maxWidth: 560,
      ),
      builder: (ctx) => SafeArea(
        child: _QueueList(
          queue: _queue,
          currentId: _channel.id,
          onSelect: (i) {
            Navigator.of(ctx).pop();
            _switchTo(i);
          },
        ),
      ),
    ).whenComplete(_scheduleHide);
  }

  // ═════════════ البناء ═════════════

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    _applyUiMode(landscape);

    final videoArea = _videoArea(s, landscape);

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: landscape
            ? videoArea
            : SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    AspectRatio(aspectRatio: 16 / 9, child: videoArea),
                    Expanded(
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: _portraitPanel(s),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _videoArea(AppStrings s, bool landscape) {
    final keepOn = ref.read(settingsProvider).keepScreenOn;

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onVerticalDragStart:
              _locked ? null : (d) => _dragLeft = d.localPosition.dx < w / 2,
          onVerticalDragUpdate: _locked ? null : (d) => _onDrag(d, h),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              Positioned.fill(
                child: Video(
                  controller: _video,
                  controls: NoVideoControls,
                  fit: _fit,
                  wakelock: keepOn,
                ),
              ),
              _statusLayer(s),
              _gestureLayer(),
              _controlsLayer(s, landscape),
            ],
          ),
        );
      },
    );
  }

  // ─── حالة التحميل والأخطاء ───

  Widget _statusLayer(AppStrings s) {
    if (_status == _Status.playing) return const SizedBox.shrink();

    if (_status == _Status.error) {
      return Positioned.fill(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 44),
              const SizedBox(height: 10),
              Text(
                s.playbackError,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _retryNow,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(s.retry),
              ),
            ],
          ),
        ),
      );
    }

    final label = _status == _Status.reconnecting
        ? s.reconnecting
        : (_status == _Status.buffering ? s.buffering : s.loading);

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── مؤشر السطوع والصوت ───

  Widget _gestureLayer() {
    final kind = _gesture;
    if (kind == null) return const SizedBox.shrink();

    final IconData icon = kind == _GestureKind.brightness
        ? Icons.brightness_6_rounded
        : (_gestureValue <= 0
            ? Icons.volume_off_rounded
            : Icons.volume_up_rounded);

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 30),
                const SizedBox(height: 10),
                SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _gestureValue,
                      minHeight: 5,
                      backgroundColor: Colors.white24,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.secondary),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_gestureValue * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── أزرار التحكم ───

  Widget _btn(
    IconData icon,
    VoidCallback? onTap, {
    double size = 26,
    String? tooltip,
    Color color = Colors.white,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap == null
          ? null
          : () {
              onTap();
              _scheduleHide();
            },
      iconSize: size,
      color: color,
      disabledColor: Colors.white30,
      icon: Icon(icon),
    );
  }

  Widget _liveBadge(AppStrings s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.live,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        s.live,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _controlsLayer(AppStrings s, bool landscape) {
    final visible = _controlsVisible;

    // وضع القفل: زر فتح القفل فقط.
    if (_locked) {
      return Positioned.fill(
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: AppConstants.animFast,
            child: SafeArea(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: _btn(
                      Icons.lock_rounded,
                      _toggleLock,
                      tooltip: s.unlockControls,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final favIds = ref.watch(favoriteIdsProvider);
    final isFav = favIds.contains(_channel.id);
    final hasQueue = _queue.length > 1;
    final playing = _player.state.playing;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppConstants.animFast,
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: AppColors.playerShade),
            child: SafeArea(
              child: Column(
                children: [
                  // الشريط العلوي
                  Row(
                    children: [
                      _btn(Icons.arrow_back_rounded, _onBack),
                      Expanded(
                        child: Text(
                          _channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _liveBadge(s),
                      _btn(
                        isFav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        () => ref
                            .read(favoritesProvider.notifier)
                            .toggle(_channel),
                        color: isFav ? AppColors.live : Colors.white,
                      ),
                    ],
                  ),

                  // الوسط
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _btn(
                          Icons.skip_previous_rounded,
                          hasQueue ? _previous : null,
                          size: 38,
                          tooltip: s.previousChannel,
                        ),
                        const SizedBox(width: 18),
                        Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.brandGradient,
                          ),
                          child: _btn(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            _player.playOrPause,
                            size: 44,
                          ),
                        ),
                        const SizedBox(width: 18),
                        _btn(
                          Icons.skip_next_rounded,
                          hasQueue ? _next : null,
                          size: 38,
                          tooltip: s.nextChannel,
                        ),
                      ],
                    ),
                  ),

                  // الشريط السفلي
                  Row(
                    children: [
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: _cycleAspect,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.aspect_ratio_rounded, size: 20),
                        label: Text(_aspectLabel(s)),
                      ),
                      _btn(
                        Icons.lock_open_rounded,
                        _toggleLock,
                        size: 22,
                        tooltip: s.lockControls,
                      ),
                      const Spacer(),
                      if (landscape && hasQueue)
                        _btn(
                          Icons.format_list_bulleted_rounded,
                          _openQueueSheet,
                          size: 24,
                          tooltip: s.channelList,
                        ),
                      _btn(
                        landscape
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        _toggleFullscreen,
                        size: 28,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── اللوحة السفلية في الوضع الطولي ───

  Widget _portraitPanel(AppStrings s) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withOpacity(0.58);
    final favIds = ref.watch(favoriteIdsProvider);
    final isFav = favIds.contains(_channel.id);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 10),
          child: Row(
            children: [
              ChannelLogo(channel: _channel, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _channel.hasGroup ? _channel.group : s.nowPlaying,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () =>
                    ref.read(favoritesProvider.notifier).toggle(_channel),
                icon: Icon(
                  isFav
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFav ? AppColors.live : muted,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        if (_queue.length > 1)
          Expanded(
            child: _QueueList(
              queue: _queue,
              currentId: _channel.id,
              onSelect: _switchTo,
              showTitle: true,
            ),
          )
        else
          const Spacer(),
      ],
    );
  }
}

/// قائمة القنوات القابلة للتبديل (في اللوحة السفلية أو النافذة).
class _QueueList extends ConsumerStatefulWidget {
  final List<Channel> queue;
  final String currentId;
  final ValueChanged<int> onSelect;
  final bool showTitle;

  const _QueueList({
    required this.queue,
    required this.currentId,
    required this.onSelect,
    this.showTitle = true,
  });

  @override
  ConsumerState<_QueueList> createState() => _QueueListState();
}

class _QueueListState extends ConsumerState<_QueueList> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final idx = widget.queue.indexWhere((c) => c.id == widget.currentId);
    final offset = math.max(0, idx) * 82.0;
    _scroll = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final favIds = ref.watch(favoriteIdsProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTitle)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 6),
            child: Text(
              '${s.channelList} • ${s.channelsCount(widget.queue.length)}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: widget.queue.length,
            itemBuilder: (context, i) {
              final c = widget.queue[i];
              return ChannelTile(
                key: ValueKey(c.id),
                channel: c,
                isPlaying: c.id == widget.currentId,
                isFavorite: favIds.contains(c.id),
                onTap: () => widget.onSelect(i),
                onToggleFavorite: () =>
                    ref.read(favoritesProvider.notifier).toggle(c),
                onLongPress: () =>
                    showChannelActions(context, c, allowHide: false),
              );
            },
          ),
        ),
      ],
    );
  }
}
