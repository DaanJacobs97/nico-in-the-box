import 'package:flutter/material.dart';

import '../../net/protocol.dart';

/// Gold for "this is the board being fired at" and "your turn".
const seaTurnColor = Color(0xFFFFC940);

/// How long a shot's toast stays up; its square flashes for the first part.
const seaShotLife = Duration(seconds: 3);

/// The fleet being fired at right now, or null when the game is over or
/// there is more than one fleet left to pick from (free-for-all).
String? seaTargetOf(Json view) {
  final turn = view['turn'] as String?;
  if (turn == null || view['winner'] != null) return null;
  final boards = view['boards']! as Json;
  final targets = [
    for (final id in (view['order']! as List<Object?>).cast<String>())
      if (id != turn &&
          ((boards[id]! as Json)['afloat']! as List<Object?>).isNotEmpty)
        id,
  ];
  return targets.length == 1 ? targets.single : null;
}

/// A coloured pill with the turn text. Gold when [active] (it's your turn,
/// or on the shared screen always), pulsing gently when [pulse] unless the
/// system asks for less motion.
class TurnBanner extends StatefulWidget {
  const TurnBanner({
    super.key,
    required this.text,
    this.active = true,
    this.pulse = false,
    this.style,
  });

  final String text;
  final bool active;
  final bool pulse;
  final TextStyle? style;

  @override
  State<TurnBanner> createState() => _TurnBannerState();
}

class _TurnBannerState extends State<TurnBanner>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TurnBanner old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.pulse && !MediaQuery.disableAnimationsOf(context)) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (widget.style ?? theme.textTheme.titleLarge!).copyWith(
      fontWeight: FontWeight.w800,
      color: widget.active ? Colors.black : theme.colorScheme.onSurface,
    );
    return ScaleTransition(
      scale: Tween(
        begin: 1.0,
        end: 1.06,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: style.fontSize! * 0.9,
          vertical: style.fontSize! * 0.3,
        ),
        decoration: BoxDecoration(
          color: widget.active
              ? seaTurnColor
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(widget.text, style: style, textAlign: TextAlign.center),
      ),
    );
  }
}

/// A shot that arrived in the last [seaShotLife]; [life] runs from 0 to 1
/// over that time.
class FreshShot {
  const FreshShot(this.shot, this.life);

  final Json shot;
  final Animation<double> life;

  int get cell => shot['cell']! as int;
  String get target => shot['target']! as String;
}

/// Watches a Sea Siege `log` and hands [builder] the shots that arrived
/// recently. Shots already in the log when it first builds (opening the
/// screen or reconnecting mid-game) are not replayed.
class SeaShotFeed extends StatefulWidget {
  const SeaShotFeed({super.key, required this.log, required this.builder});

  final List<Json> log;
  final Widget Function(BuildContext context, List<FreshShot> fresh) builder;

  @override
  State<SeaShotFeed> createState() => _SeaShotFeedState();
}

class _SeaShotFeedState extends State<SeaShotFeed>
    with TickerProviderStateMixin {
  late int _seen;
  final _fresh = <(FreshShot, AnimationController)>[];

  static int _latest(List<Json> log) => log.isEmpty ? 0 : log.last['n']! as int;

  @override
  void initState() {
    super.initState();
    _seen = _latest(widget.log);
  }

  @override
  void didUpdateWidget(SeaShotFeed old) {
    super.didUpdateWidget(old);
    final latest = _latest(widget.log);
    if (latest < _seen) _seen = 0; // a new game started
    for (final shot in widget.log) {
      if ((shot['n']! as int) <= _seen) continue;
      final controller = AnimationController(
        vsync: this,
        duration: seaShotLife,
      );
      final entry = (FreshShot(shot, controller), controller);
      _fresh.add(entry);
      controller.forward().whenComplete(() {
        if (!mounted) return;
        setState(() => _fresh.remove(entry));
        controller.dispose();
      });
    }
    _seen = latest;
  }

  @override
  void dispose() {
    for (final (_, controller) in _fresh) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, [for (final (shot, _) in _fresh) shot]);
}

/// [child] with the newest two of [toasts] floating over its bottom edge.
/// They ignore taps; pick which board they sit on so they never cover
/// squares a player may tap.
class SeaToastLayer extends StatelessWidget {
  const SeaToastLayer({
    super.key,
    required this.toasts,
    required this.describe,
    required this.child,
    this.style,
  });

  final List<FreshShot> toasts;
  final String Function(Json shot) describe;
  final Widget child;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final shown = toasts.length > 2
        ? toasts.sublist(toasts.length - 2)
        : toasts;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final toast in shown)
                  _Toast(
                    key: ValueKey('sea-toast-${toast.shot['n']}'),
                    toast: toast,
                    text: describe(toast.shot),
                    style: style,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({
    super.key,
    required this.toast,
    required this.text,
    this.style,
  });

  final FreshShot toast;
  final String text;
  final TextStyle? style;

  static final _fade = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 5),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 70),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
  ]);

  @override
  Widget build(BuildContext context) {
    final result = toast.shot['result'];
    return FadeTransition(
      opacity: _fade.animate(toast.life),
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE6101018),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: result == 'miss' ? Colors.white38 : const Color(0xFFE53935),
            width: 2,
          ),
        ),
        child: Text(
          text,
          style: (style ?? const TextStyle()).copyWith(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// A board with its [title] above it. The board being fired at
/// ([target]) gets a crosshair by its title; a [dimmed] board fades back.
/// [toasts] float over the board's bottom edge.
class SeaBoardPanel extends StatelessWidget {
  const SeaBoardPanel({
    super.key,
    required this.title,
    required this.board,
    this.target = false,
    this.dimmed = false,
    this.toasts = const [],
    required this.describe,
    this.style,
  });

  final String title;
  final Widget board;
  final bool target;
  final bool dimmed;
  final List<FreshShot> toasts;
  final String Function(Json shot) describe;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final titleStyle = (style ?? DefaultTextStyle.of(context).style).copyWith(
      fontWeight: FontWeight.w700,
    );
    // Dimming fades the title and board but not the toasts: a miss passes
    // the turn, so its board dims while its toast is still up.
    Widget fade(Widget child) => AnimatedOpacity(
      opacity: dimmed ? 0.45 : 1,
      duration: const Duration(milliseconds: 250),
      child: child,
    );
    return Column(
      children: [
        fade(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (target) ...[
                Icon(
                  Icons.gps_fixed,
                  key: const ValueKey('sea-target-badge'),
                  color: seaTurnColor,
                  size: titleStyle.fontSize! * 1.2,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(child: Text(title, style: titleStyle)),
            ],
          ),
        ),
        Expanded(
          child: SeaToastLayer(
            toasts: toasts,
            describe: describe,
            style: style,
            child: fade(board),
          ),
        ),
      ],
    );
  }
}
