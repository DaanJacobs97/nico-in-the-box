part of 'tacticalvoxelrpg_view.dart';

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
