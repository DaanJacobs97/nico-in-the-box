part of 'tacticalvoxelrpg_view.dart';

class _UnitActivationCard extends StatelessWidget {
  const _UnitActivationCard({
    super.key,
    required this.unit,
    required this.selected,
    required this.disabled,
    required this.compact,
    required this.onTap,
    this.handCard = false,
  });

  final Map<String, Object?> unit;
  final bool selected;
  final bool disabled;
  final bool compact;
  final bool handCard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final art = _characterPortraitFor(unit);
    final fill = unit['completed'] == true;
    final health = (unit['hp'] as int) / (unit['maxHp'] as int);
    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: compact
          ? 64
          : handCard
          ? 120
          : 174,
      height: compact
          ? 90
          : handCard
          ? 190
          : 72,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: selected
              ? const [Color(0xff392b4b), Color(0xff20182c)]
              : const [Color(0xff282235), Color(0xff191523)],
        ),
        border: Border.all(
          color: selected ? const Color(0xffd2b9ed) : const Color(0xff655675),
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? const [BoxShadow(color: Color(0x33c5a8e4), blurRadius: 15)]
            : null,
      ),
      padding: const EdgeInsets.all(6),
      child: Opacity(
        opacity: disabled || fill ? 0.42 : 1,
        child: compact
            ? Column(
                children: [
                  Expanded(child: _unitArt(art)),
                  Text(
                    unit['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Georgia', fontSize: 9),
                  ),
                  Text(
                    '${unit['hp']}/${unit['maxHp']}',
                    style: const TextStyle(
                      color: Color(0xffd7c9e5),
                      fontSize: 8,
                    ),
                  ),
                ],
              )
            : handCard
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 76, child: _unitArt(art)),
                  Text(
                    (unit['role'] as String).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xffc9b3e1),
                      fontSize: 7,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    unit['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Georgia', fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    '${unit['hp']}/${unit['maxHp']} HP · 2 AP',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xffd7c9e5),
                      fontSize: 8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: health,
                      minHeight: 4,
                      backgroundColor: const Color(0xff40364b),
                      color: const Color(0xffbea3df),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'MOV ${unit['movement']} · RANGE ${unit['minimumRange']}–${unit['range']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xffb7a7c9),
                      fontSize: 7,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  SizedBox(width: 42, child: _unitArt(art)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          unit['name'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${unit['hp']}/${unit['maxHp']} HP · MOV ${unit['movement']}',
                          style: const TextStyle(
                            color: Color(0xffc7b9d5),
                            fontSize: 8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: health,
                            minHeight: 4,
                            backgroundColor: const Color(0xff40364b),
                            color: const Color(0xffbea3df),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    selected ? Icons.check_circle : Icons.play_circle_outline,
                    color: const Color(0xffd2b9ed),
                    size: 17,
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
      child: GestureDetector(onTap: onTap, child: face),
    );
  }

  Widget _unitArt(String? art) => art == null
      ? const Icon(Icons.person_outline, color: Color(0xffb9a8ca))
      : Image.asset(
          art,
          package: 'nico_shared',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.person_outline),
        );
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
    required this.targeting,
    required this.onTap,
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
  final bool targeting;
  final VoidCallback onTap;
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
          colors: [Color(0xff493957), Color(0xff292137), Color(0xff171321)],
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
        opacity: targeting
            ? 0.3
            : disabled
            ? 0.55
            : 1,
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
                        colors: [Color(0x449a80bf), Color(0xff171321)],
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
                    colors: [Color(0xff77628e), Color(0xff21192e)],
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
                onTap: targeting ? null : onRetain,
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
                      style: TextStyle(color: Color(0xff191321), fontSize: 7),
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
      maxSimultaneousDrags: disabled || targeting ? 0 : 1,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.rotate(angle: -0.025, child: face),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: face),
      child: GestureDetector(onTap: targeting ? null : onTap, child: face),
    );
  }
}
