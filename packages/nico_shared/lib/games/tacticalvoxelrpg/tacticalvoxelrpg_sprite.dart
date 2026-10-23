part of 'tacticalvoxelrpg_view.dart';

String? _characterPortraitFor(Map<String, Object?>? unit) {
  if (unit == null) return null;
  final enemy = unit['owner'] == tacticalAiId;
  final name = switch ((enemy, unit['kind'])) {
    (false, 'closeCombat') => 'aldric',
    (false, 'ranged') => 'seren',
    (false, 'trapper') => 'mora',
    (true, 'closeCombat') => 'hollow_guard',
    (true, 'ranged') => 'hollow_archer',
    (true, 'trapper') => 'blight_hound',
    _ => null,
  };
  return name == null ? null : 'assets/tacticalvoxelrpg/characters/$name.png';
}

const _slimeFrameCounts = {
  'idle': 9,
  'walk': 8,
  'melee': 8,
  'ranged': 8,
  'special': 11,
  'hurt': 5,
};

String _slimeAnimationFor(Map<String, Object?>? unit, Object? action) {
  if (unit == null ||
      unit['sprite'] is! String ||
      action is! Map<Object?, Object?>) {
    return 'idle';
  }
  final unitId = unit['id'];
  switch (action['type']) {
    case 'move':
      return 'idle';
    case 'trap':
      return action['unit'] == unitId ? 'special' : 'idle';
    case 'trapHit':
      return action['unit'] == unitId ? 'hurt' : 'idle';
    case 'attack':
      if (action['target'] == unitId) return 'hurt';
      if (action['unit'] != unitId) return 'idle';
      return switch (unit['kind']) {
        'closeCombat' => 'melee',
        'ranged' => 'ranged',
        _ => 'special',
      };
    default:
      return 'idle';
  }
}

String _characterAnimationFor(
  Map<String, Object?>? unit,
  Object? action, {
  bool moving = false,
}) {
  if (moving) return 'walk';
  if (unit == null || action is! Map<Object?, Object?>) return 'idle';
  final unitId = unit['id'];
  if (action['type'] == 'attack') {
    if (action['target'] == unitId) return 'hurt';
    if (action['unit'] == unitId) return 'attack';
  }
  if (action['type'] == 'trapHit' && action['unit'] == unitId) {
    return 'hurt';
  }
  if (action['type'] == 'trap' && action['unit'] == unitId) {
    return 'special';
  }
  return 'idle';
}

class _TacticalCharacterArt extends StatefulWidget {
  const _TacticalCharacterArt({
    required this.asset,
    required this.animation,
    required this.event,
    required this.width,
    required this.height,
    this.attackDirection = 1,
  });

  final String asset;
  final String animation;
  final int event;
  final double width;
  final double height;
  final double attackDirection;

  @override
  State<_TacticalCharacterArt> createState() => _TacticalCharacterArtState();
}

class _TacticalCharacterArtState extends State<_TacticalCharacterArt>
    with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat(reverse: true);
  late final AnimationController _action = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  @override
  void didUpdateWidget(covariant _TacticalCharacterArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event != widget.event &&
        (widget.animation == 'attack' ||
            widget.animation == 'hurt' ||
            widget.animation == 'special')) {
      _action.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    _action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_idle, _action]),
    child: Image.asset(
      widget.asset,
      package: 'nico_shared',
      width: widget.width,
      height: widget.height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      cacheWidth: (widget.width * MediaQuery.devicePixelRatioOf(context))
          .round(),
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    ),
    builder: (context, image) {
      final progress = Curves.easeOut.transform(_action.value);
      var dx = 0.0;
      var dy = -3 * sin(_idle.value * pi);
      var scale = 1.0;
      if (widget.animation == 'walk') {
        dx = 2.5 * sin(_idle.value * pi * 2);
        dy = -2 * sin(_idle.value * pi * 2).abs();
      } else if (widget.animation == 'attack') {
        dx = widget.attackDirection * 20 * sin(progress * pi);
        scale += 0.08 * sin(progress * pi);
      } else if (widget.animation == 'hurt') {
        dx = 8 * sin(progress * pi * 5) * (1 - progress);
      } else if (widget.animation == 'special') {
        dy -= 12 * sin(progress * pi);
        scale += 0.1 * sin(progress * pi);
      }
      final art = widget.animation == 'hurt' && _action.isAnimating
          ? ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0x66ff554d),
                BlendMode.srcATop,
              ),
              child: image,
            )
          : image;
      return Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.scale(scale: scale, child: art),
      );
    },
  );
}

class _TacticalSlimeSprite extends StatefulWidget {
  const _TacticalSlimeSprite({
    required this.sprite,
    required this.animation,
    required this.event,
    required this.size,
    this.repeat = false,
  });

  final String sprite;
  final String animation;
  final int event;
  final double size;
  final bool repeat;

  @override
  State<_TacticalSlimeSprite> createState() => _TacticalSlimeSpriteState();
}

class _TacticalSlimeSpriteState extends State<_TacticalSlimeSprite> {
  Timer? _timer;
  String _animation = 'idle';
  int _frame = 0;

  int get _frameCount =>
      _slimeFrameCounts[_animation] ?? _slimeFrameCounts['idle']!;

  @override
  void initState() {
    super.initState();
    _play(widget.animation);
  }

  @override
  void didUpdateWidget(covariant _TacticalSlimeSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sprite != widget.sprite ||
        oldWidget.animation != widget.animation ||
        oldWidget.event != widget.event ||
        oldWidget.repeat != widget.repeat) {
      _play(widget.animation);
    }
  }

  void _play(String animation) {
    _timer?.cancel();
    _animation = _slimeFrameCounts.containsKey(animation) ? animation : 'idle';
    _frame = 0;
    if (mounted) setState(() {});
    if (_animation == 'idle' || widget.repeat) {
      _timer = Timer.periodic(const Duration(milliseconds: 125), (_) {
        if (mounted) setState(() => _frame = (_frame + 1) % _frameCount);
      });
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 125), (timer) {
      if (!mounted) return timer.cancel();
      if (_frame + 1 >= _frameCount) {
        timer.cancel();
        _play('idle');
      } else {
        setState(() => _frame++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _frameCount;
    final frameSize = widget.size;
    return SizedBox(
      width: frameSize,
      height: frameSize,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: -_frame * frameSize,
              top: 0,
              width: count * frameSize,
              height: frameSize,
              child: Image.asset(
                'assets/tacticalvoxelrpg/slimes/${widget.sprite}/$_animation.png',
                package: 'nico_shared',
                fit: BoxFit.fill,
                cacheWidth: (count * frameSize).ceil(),
                cacheHeight: frameSize.ceil(),
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
