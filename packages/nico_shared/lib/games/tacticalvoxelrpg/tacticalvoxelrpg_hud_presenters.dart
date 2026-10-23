part of 'tacticalvoxelrpg_view.dart';

class _HudLabel extends StatelessWidget {
  const _HudLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xff959b8e),
      fontSize: 9,
      letterSpacing: 2,
    ),
  );
}

class _TacticalPortraitPanel extends StatelessWidget {
  const _TacticalPortraitPanel({required this.unit, required this.action});

  final Map<String, Object?> unit;
  final Object? action;

  @override
  Widget build(BuildContext context) {
    final asset = _characterPortraitFor(unit);
    final hp = unit['hp'] as int;
    final maxHp = unit['maxHp'] as int;
    return IgnorePointer(
      child: SizedBox(
        width: 205,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 242,
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.black, Colors.transparent],
                  stops: [0, 0.72, 1],
                ).createShader(bounds),
                blendMode: BlendMode.dstIn,
                child: asset == null
                    ? const SizedBox.shrink()
                    : _TacticalCharacterArt(
                        asset: asset,
                        animation: _characterAnimationFor(unit, action),
                        event: _lastEvent(action) ?? 0,
                        width: 205,
                        height: 255,
                      ),
              ),
            ),
            Text(
              (unit['role'] as String).toUpperCase(),
              style: const TextStyle(
                color: Color(0xffc0ac7e),
                fontSize: 9,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              unit['name'] as String,
              style: const TextStyle(fontFamily: 'Georgia', fontSize: 28),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.favorite, color: Color(0xffa3af80), size: 14),
                const SizedBox(width: 6),
                Text(
                  '$hp / $maxHp HEALTH',
                  style: const TextStyle(
                    color: Color(0xffaab2a0),
                    fontSize: 10,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: maxHp == 0 ? 0 : hp / maxHp,
                minHeight: 4,
                backgroundColor: const Color(0xff333d32),
                color: const Color(0xffa3af80),
              ),
            ),
            const SizedBox(height: 12),
            const _HudLabel('EQUIPPED WEAPON'),
            const SizedBox(height: 5),
            Text(
              unit['weapon'] as String,
              style: const TextStyle(color: Color(0xffd7d8c8), fontSize: 11),
            ),
            const SizedBox(height: 3),
            Text(
              'Range ${unit['minimumRange']}–${unit['range']} tiles  ·  ${unit['mana']} mana',
              style: const TextStyle(color: Color(0xffd6bd84), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _SquadHealthRow extends StatelessWidget {
  const _SquadHealthRow({required this.units, required this.activeId});

  final List<Map<String, Object?>> units;
  final Object? activeId;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final unit in units)
          Container(
            width: 66,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xd9141b19),
              border: Border.all(
                color: unit['id'] == activeId
                    ? const Color(0xffcdb37b)
                    : const Color(0xff657364),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 51,
                  child: _characterPortraitFor(unit) == null
                      ? const Icon(Icons.person_outline)
                      : Image.asset(
                          _characterPortraitFor(unit)!,
                          package: 'nico_shared',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (unit['hp'] as int) / (unit['maxHp'] as int),
                    minHeight: 4,
                    backgroundColor: const Color(0xff333d32),
                    color: const Color(0xffa3af80),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        unit['name'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 8),
                      ),
                    ),
                    Text(
                      '${unit['hp']}/${unit['maxHp']}',
                      style: const TextStyle(fontSize: 7),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _BattleStatusCard extends StatelessWidget {
  const _BattleStatusCard({required this.phase, required this.turn});

  final String phase;
  final int turn;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xe5101714),
        border: Border.all(color: const Color(0x40888a63)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            phase.toUpperCase(),
            style: const TextStyle(
              color: Color(0xffaab2a0),
              fontSize: 9,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'TURN ${turn.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: Color(0xffe0d5b4),
              fontFamily: 'Georgia',
              fontSize: 17,
            ),
          ),
        ],
      ),
    ),
  );
}
