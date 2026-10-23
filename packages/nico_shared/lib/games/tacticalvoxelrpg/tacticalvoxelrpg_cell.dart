part of 'tacticalvoxelrpg_view.dart';

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: enabled ? onPressed : null,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: selected
        ? FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          )
        : null,
  );
}

class _UnitActivationCard extends StatelessWidget {
  const _UnitActivationCard({required this.unit, required this.onTap});

  final Map<String, Object?> unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: SizedBox(
      width: 126,
      child: OutlinedButton(
        key: ValueKey('tacticalvoxelrpg-activate-${unit['id']}'),
        onPressed: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              unit['name'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              '${unit['hp']}/${unit['maxHp']} HP',
              style: const TextStyle(fontSize: 10),
            ),
            Text(
              '${unit['energy']} AP · ${unit['handSize']} cards',
              style: const TextStyle(fontSize: 9),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TacticalHandCard extends StatelessWidget {
  const _TacticalHandCard({
    required this.card,
    required this.movement,
    required this.selected,
    required this.retained,
    required this.onTap,
    required this.onRetain,
  });

  final Map<String, Object?> card;
  final int movement;
  final bool selected;
  final bool retained;
  final VoidCallback onTap;
  final VoidCallback onRetain;

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? const Color(0xffe5cd98)
        : retained
        ? const Color(0xffb9a270)
        : const Color(0xff66705b);
    final description = (card['text'] as String).replaceAll(
      '{mov}',
      '$movement',
    );
    return SizedBox(
      width: 132,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Material(
          color: selected ? const Color(0xff344137) : const Color(0xff202a23),
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: border, width: selected ? 2 : 1),
                borderRadius: BorderRadius.circular(9),
              ),
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          card['type'] as String,
                          style: const TextStyle(fontSize: 8, letterSpacing: 1),
                        ),
                      ),
                      Text('${card['cost']} AP'),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        card['icon'] as String,
                        style: const TextStyle(
                          fontSize: 32,
                          color: Color(0xffc1bd9f),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    card['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Georgia', fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, height: 1.25),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: onRetain,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3, left: 8),
                        child: Text(
                          retained ? '◆ RETAINED' : '◇ RETAIN',
                          style: const TextStyle(
                            fontSize: 8,
                            color: Color(0xffbcad88),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    required this.attackTarget,
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
  final bool attackTarget;
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
        color: color,
        border: Border.all(
          color: route
              ? Colors.cyanAccent
              : attackTarget
              ? Colors.redAccent
              : reachable
              ? Colors.lightBlueAccent
              : wall
              ? const Color(0xff524d5b)
              : const Color(0xff211e25),
          width: route || attackTarget ? 2 : 1,
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
