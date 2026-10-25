part of 'tacticalvoxelrpg_view.dart';

class _OverlayPanel extends StatelessWidget {
  const _OverlayPanel({
    required this.child,
    this.padding = const EdgeInsets.all(8),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xe61c1825),
    borderRadius: BorderRadius.circular(12),
    elevation: 8,
    child: Padding(padding: padding, child: child),
  );
}

class _MapZoomControls extends StatelessWidget {
  const _MapZoomControls({
    required this.keyPrefix,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final String keyPrefix;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xdd1c1825),
    borderRadius: BorderRadius.circular(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('$keyPrefix-zoom-in'),
          tooltip: 'Zoom in',
          visualDensity: VisualDensity.compact,
          onPressed: onZoomIn,
          icon: const Icon(Icons.add),
        ),
        IconButton(
          key: ValueKey('$keyPrefix-zoom-reset'),
          tooltip: 'Reset zoom',
          visualDensity: VisualDensity.compact,
          onPressed: onReset,
          icon: const Icon(Icons.fit_screen),
        ),
        IconButton(
          key: ValueKey('$keyPrefix-zoom-out'),
          tooltip: 'Zoom out',
          visualDensity: VisualDensity.compact,
          onPressed: onZoomOut,
          icon: const Icon(Icons.remove),
        ),
      ],
    ),
  );
}

class _TacticalUnitMarker extends StatelessWidget {
  const _TacticalUnitMarker({required this.unit, required this.size});

  final Map<String, Object?> unit;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mark = switch (unit['kind']) {
      'closeCombat' => 'V',
      'ranged' => 'R',
      'trapper' => 'T',
      _ => '',
    };
    final enemy = unit['owner'] == tacticalAiId;
    return Center(
      child: Text(
        mark,
        style: TextStyle(
          color: enemy ? const Color(0xffff7168) : const Color(0xffffd166),
          fontWeight: FontWeight.w900,
          fontSize: size * 0.42,
          height: 1,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
    );
  }
}

class _VoxelCell extends StatelessWidget {
  const _VoxelCell({
    super.key,
    required this.terrain,
    required this.unit,
    this.showUnit = true,
    required this.trap,
    required this.reachable,
    required this.route,
    required this.routeArrow,
    required this.routeDestination,
    required this.attackTarget,
    required this.attackRange,
    this.trapTarget = false,
    required this.damage,
    required this.damageEvent,
    required this.unitAnimation,
    required this.tileSize,
  });

  final String terrain;
  final Map<String, Object?>? unit;
  final bool showUnit;
  final bool trap;
  final bool reachable;
  final bool route;
  final double? routeArrow;
  final bool routeDestination;
  final bool attackTarget;
  final bool attackRange;
  final bool trapTarget;
  final int? damage;
  final int? damageEvent;
  final String unitAnimation;
  final double tileSize;

  @override
  Widget build(BuildContext context) {
    final wall = terrain == 'wall';
    final color = switch (terrain) {
      'water' => const Color(0xff235f8c),
      'cliff' => const Color(0xff34313c),
      'grass' => const Color(0xff607b4c),
      'deepGrass' => const Color(0xff748844),
      'forest' => const Color(0xff294c3b),
      'rock' => const Color(0xff817b72),
      'marsh' => const Color(0xff576a50),
      'path' => const Color(0xff94816a),
      'bank' => const Color(0xff89785d),
      'bridge' => const Color(0xffaa8256),
      'brush' => const Color(0xff718051),
      'wall' => const Color(0xff34313c),
      'rubble' => const Color(0xff89715d),
      _ => const Color(0xff59515a),
    };
    final terrainIcon = switch (terrain) {
      'water' => Icons.water,
      'forest' => Icons.forest,
      'cliff' => Icons.terrain,
      'rock' => Icons.circle,
      'marsh' => Icons.grass,
      _ => null,
    };
    final mark = switch (unit?['kind']) {
      'closeCombat' => 'V',
      'ranged' => 'R',
      'trapper' => 'T',
      _ => '',
    };
    final ai = unit?['owner'] == tacticalAiId;
    final unitColor = ai ? const Color(0xffff7168) : const Color(0xffffd166);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: trapTarget
            ? Color.lerp(color, const Color(0xffd83353), 0.52)
            : attackRange
            ? Color.lerp(color, const Color(0xffc74462), 0.36)
            : reachable
            ? Color.lerp(color, const Color(0xfff2cf52), 0.38)
            : route
            ? Color.lerp(color, const Color(0xffdbb450), 0.3)
            : color,
        border: Border.all(
          color: route
              ? const Color(0xffffd56b)
              : trapTarget
              ? const Color(0xffff4c69)
              : attackTarget
              ? const Color(0xffff536b)
              : attackRange
              ? const Color(0xffd94159)
              : reachable
              ? const Color(0xffffdf70)
              : wall
              ? const Color(0xff524d5b)
              : const Color(0xff211e25),
          width: route || attackTarget || attackRange || trapTarget ? 2 : 1,
        ),
        boxShadow: wall
            ? const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 2,
                  offset: Offset(1, 2),
                ),
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (tileSize >= 24 && terrainIcon != null)
            Icon(
              terrainIcon,
              color: Colors.white.withValues(alpha: 0.18),
              size: tileSize * 0.65,
            ),
          if (trap)
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.deepOrange,
              size: tileSize * 0.55,
            ),
          if (routeArrow != null)
            Transform.rotate(
              angle: routeArrow!,
              child: Icon(
                routeDestination
                    ? Icons.arrow_circle_right
                    : Icons.arrow_right_alt,
                color: const Color(0xffffdf70),
                size: tileSize * 0.58,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
              ),
            ),
          if (unit != null && showUnit)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unit!['sprite'] is String)
                  _TacticalSlimeSprite(
                    sprite: unit!['sprite']! as String,
                    animation: unitAnimation,
                    event: damageEvent ?? 0,
                    size: tileSize * 0.68,
                  )
                else
                  Text(
                    mark,
                    style: TextStyle(
                      color: unitColor,
                      fontWeight: FontWeight.w900,
                      fontSize: tileSize * 0.42,
                      height: 1,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 3),
                      ],
                    ),
                  ),
                if (tileSize >= 36)
                  Text(
                    '${unit!['hp']} HP · ${unit!['energy']} E',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: tileSize * 0.13,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
              ],
            ),
          if (damage != null)
            Positioned(
              top: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 900),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.55),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  '-$damage',
                  key: ValueKey('tacticalvoxelrpg-damage-$damageEvent-$damage'),
                  style: TextStyle(
                    color: const Color(0xffff655b),
                    fontWeight: FontWeight.w900,
                    fontSize: tileSize * 0.32,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
