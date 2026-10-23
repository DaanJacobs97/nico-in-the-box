part of 'tacticalvoxelrpg_view.dart';

class _UnitActivationCard extends StatelessWidget {
  const _UnitActivationCard({
    super.key,
    required this.unit,
    required this.selected,
    required this.disabled,
    required this.compact,
    required this.onTap,
  });

  final Map<String, Object?> unit;
  final bool selected;
  final bool disabled;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final art = _characterPortraitFor(unit);
    final fill = unit['completed'] == true;
    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: compact ? 64 : 56,
      height: compact ? 90 : 146,
      decoration: BoxDecoration(
        color: selected ? const Color(0xff293026) : const Color(0xff1b2420),
        border: Border.all(
          color: selected ? const Color(0xffc4aa72) : const Color(0xff4b5548),
        ),
        boxShadow: selected
            ? const [BoxShadow(color: Color(0x22b69b4b), blurRadius: 18)]
            : null,
      ),
      padding: const EdgeInsets.all(5),
      child: Opacity(
        opacity: disabled || fill ? 0.35 : 1,
        child: Column(
          children: [
            SizedBox(
              height: compact ? 31 : 67,
              child: art == null
                  ? const Icon(Icons.person_outline, color: Color(0xff909782))
                  : Image.asset(
                      art,
                      package: 'nico_shared',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.person_outline),
                    ),
            ),
            Text(
              unit['name'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: compact ? 9 : 11,
              ),
            ),
            const Spacer(),
            Text(
              '${unit['hp']}/${unit['maxHp']} HP',
              style: const TextStyle(color: Color(0xffaab2a0), fontSize: 8),
            ),
            SizedBox(height: compact ? 2 : 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (unit['hp'] as int) / (unit['maxHp'] as int),
                minHeight: 4,
                backgroundColor: const Color(0xff333d32),
                color: const Color(0xffa3af80),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'MOV ${unit['movement']} · MP ${unit['mana']}',
              maxLines: 1,
              style: const TextStyle(color: Color(0xffaab2a0), fontSize: 7),
            ),
          ],
        ),
      ),
    );
    return Draggable<_TacticalDragPayload>(
      data: _TacticalDragPayload.unit(unit['id']! as String),
      maxSimultaneousDrags: disabled ? 0 : 1,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.rotate(angle: -0.04, child: face),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: face),
      child: GestureDetector(onTap: disabled ? null : onTap, child: face),
    );
  }
}

class _TacticalHandCard extends StatelessWidget {
  const _TacticalHandCard({
    super.key,
    required this.unitId,
    required this.card,
    required this.movement,
    required this.compact,
    required this.selected,
    required this.retained,
    required this.disabled,
    required this.index,
    required this.onTap,
    required this.onDragStarted,
    required this.onRetain,
  });

  final String unitId;
  final Map<String, Object?> card;
  final int movement;
  final bool compact;
  final bool selected;
  final bool retained;
  final bool disabled;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDragStarted;
  final VoidCallback onRetain;

  @override
  Widget build(BuildContext context) {
    final description = (card['text'] as String).replaceAll(
      '{mov}',
      '$movement',
    );
    final cardWidth = compact ? 124.0 : 150.0;
    final cardHeight = compact ? 172.0 : 246.0;
    final tilts = const [-0.075, -0.035, 0.0, 0.035, 0.075];
    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: cardWidth,
      height: cardHeight,
      transform: Matrix4.identity()
        ..translateByDouble(
          0.0,
          selected
              ? -26.0
              : index.isOdd
              ? 2.0
              : 10.0,
          0,
          1,
        )
        ..rotateZ(selected ? 0.0 : tilts[index % tilts.length]),
      transformAlignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff586351), Color(0xff25342c), Color(0xff17231c)],
        ),
        border: Border.all(
          color: selected
              ? const Color(0xffd9c58f)
              : retained
              ? const Color(0xffb9a270)
              : const Color(0xff8e8468),
          width: selected ? 3 : 2,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          const BoxShadow(
            color: Color(0x99000000),
            blurRadius: 14,
            offset: Offset(0, 9),
          ),
          if (selected)
            const BoxShadow(color: Color(0x44c4ae63), blurRadius: 24),
          const BoxShadow(
            color: Color(0x55b0a17b),
            blurRadius: 0,
            spreadRadius: -5,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      child: Opacity(
        opacity: disabled ? 0.55 : 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  card['type'] as String,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xffb7c1ac),
                    fontSize: 8,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 7),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0x55a9a380)),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(42),
                        bottom: Radius.circular(4),
                      ),
                      gradient: const RadialGradient(
                        colors: [Color(0x4496a47b), Color(0xff17231e)],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        card['icon'] as String,
                        style: const TextStyle(
                          color: Color(0xffb5bea4),
                          fontFamily: 'Georgia',
                          fontSize: 51,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 9),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xd918251d),
                    border: Border.symmetric(
                      horizontal: BorderSide(color: Color(0xff8b8868)),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    card['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xffe1d7b8),
                      fontFamily: 'Georgia',
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xffc3c7b1),
                    fontSize: 9,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 17),
              ],
            ),
            Positioned(
              left: -19,
              top: -20,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xffc1b17e), width: 2),
                  gradient: const RadialGradient(
                    colors: [Color(0xff65775a), Color(0xff1d3023)],
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 6),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${card['cost']}',
                    style: const TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 17,
                      color: Color(0xfff0deb0),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: InkWell(
                onTap: onRetain,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    retained ? '◆ RETAINED' : '◇ RETAIN',
                    style: const TextStyle(
                      color: Color(0xffbcad88),
                      fontSize: 7,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ),
            ),
            if (retained)
              Positioned(
                top: 32,
                right: -15,
                child: Transform.rotate(
                  angle: 0.35,
                  child: Container(
                    color: const Color(0xffb89c65),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: const Text(
                      'RETAINED',
                      style: TextStyle(color: Color(0xff17221a), fontSize: 7),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Draggable<_TacticalDragPayload>(
      key: ValueKey('tacticalvoxelrpg-draggable-card-${card['id']}'),
      data: _TacticalDragPayload.card(unitId, card['id']! as int),
      maxSimultaneousDrags: disabled ? 0 : 1,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.rotate(angle: -0.025, child: face),
      ),
      onDragStarted: onDragStarted,
      childWhenDragging: Opacity(opacity: 0.25, child: face),
      child: GestureDetector(onTap: onTap, child: face),
    );
  }
}
