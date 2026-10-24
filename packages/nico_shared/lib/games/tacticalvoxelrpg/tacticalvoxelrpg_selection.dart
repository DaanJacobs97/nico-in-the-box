part of 'tacticalvoxelrpg_view.dart';

class _TacticalUnitSelectionScreen extends StatefulWidget {
  const _TacticalUnitSelectionScreen({required this.ctx});

  final GameViewContext ctx;

  @override
  State<_TacticalUnitSelectionScreen> createState() =>
      _TacticalUnitSelectionScreenState();
}

class _TacticalUnitSelectionScreenState
    extends State<_TacticalUnitSelectionScreen> {
  Timer? _timer;
  int _secondsRemaining = 60;
  bool _timeoutSent = false;
  String? _inspectedUnitId;
  String _detailTab = 'STATS';

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.ctx.view['draftSeconds'] as int? ?? 60;
    _inspectedUnitId = _ownUnits.firstOrNull?['id'] as String?;
    _startCountdown();
  }

  @override
  void didUpdateWidget(covariant _TacticalUnitSelectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serverSeconds = widget.ctx.view['draftSeconds'] as int?;
    if (serverSeconds != null && serverSeconds < _secondsRemaining) {
      _secondsRemaining = serverSeconds;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<Map<String, Object?>> get _ownUnits {
    final units = _objects(widget.ctx.view['units']);
    final ids = (widget.ctx.view['myUnits'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toSet();
    return ids.isEmpty
        ? units.where((unit) => unit['owner'] == widget.ctx.myId).toList()
        : units.where((unit) => ids.contains(unit['id'])).toList();
  }

  Set<String> get _selectedIds =>
      (widget.ctx.view['draftSelectedUnitIds'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toSet();

  Set<String> get _readyIds =>
      (widget.ctx.view['draftReadyPlayers'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toSet();

  Map<String, Object?>? get _inspectedUnit =>
      _ownUnits.where((unit) => unit['id'] == _inspectedUnitId).firstOrNull;

  void _startCountdown() {
    if (_secondsRemaining <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendTimeout());
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        setState(() => _secondsRemaining = 0);
        timer.cancel();
        _sendTimeout();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  void _sendTimeout() {
    if (_timeoutSent || !mounted) return;
    _timeoutSent = true;
    widget.ctx.sendAction({'type': 'draftTimeout'});
  }

  void _toggleUnit(Map<String, Object?> unit) {
    if (_readyIds.contains(widget.ctx.myId)) return;
    final selected = _selectedIds.contains(unit['id']);
    widget.ctx.sendAction({
      'type': 'draftSelectUnit',
      'unit': unit['id'],
      'selected': !selected,
    });
  }

  void _toggleReady() {
    final ready = _readyIds.contains(widget.ctx.myId);
    widget.ctx.sendAction({'type': 'draftReady', 'ready': !ready});
  }

  List<Map<String, Object?>> _deckFor(Map<String, Object?> unit) {
    final cards = [
      ..._objects(unit['hand']),
      ..._objects(unit['drawPile']),
      ..._objects(unit['discardPile']),
    ];
    final counts = <String, Map<String, Object?>>{};
    for (final card in cards) {
      final name = card['name']! as String;
      final entry = counts.putIfAbsent(name, () => {...card, 'copies': 0});
      entry['copies'] = (entry['copies'] as int) + 1;
    }
    return counts.values.toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.ctx.view;
    final units = _ownUnits;
    final selectedIds = _selectedIds;
    final readyIds = _readyIds;
    final isReady = readyIds.contains(widget.ctx.myId);
    final selectedCount = selectedIds.length;
    final playerCount = view['draftPlayerCount'] as int? ?? 1;
    final readyCount = view['draftReadyCount'] as int? ?? readyIds.length;
    final inspected = _inspectedUnit;
    return ColoredBox(
      color: const Color(0xff100d18),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.05, -0.75),
            radius: 1.35,
            colors: [Color(0xff2d2340), Color(0xff171321), Color(0xff100d18)],
            stops: [0, 0.48, 1],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
            child: Column(
              children: [
                _header(readyCount, playerCount),
                const SizedBox(height: 8),
                _readyPlayerStatus,
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 850) {
                        return Column(
                          children: [
                            Expanded(child: _roster(units, selectedIds)),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: min(255.0, constraints.maxHeight * 0.42),
                              child: _unitDetails(inspected),
                            ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: _roster(units, selectedIds)),
                          const SizedBox(width: 18),
                          Expanded(flex: 2, child: _unitDetails(inspected)),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                _readyFooter(
                  selectedCount: selectedCount,
                  readyCount: readyCount,
                  playerCount: playerCount,
                  isReady: isReady,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(int readyCount, int playerCount) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ASHEN OATH',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 21,
                letterSpacing: 4,
                color: Color(0xffe5d9f2),
              ),
            ),
            const SizedBox(height: 4),
            const _HudLabel('BUILD YOUR COMPANY'),
            const SizedBox(height: 5),
            Text(
              'Choose three heroes · $readyCount of $playerCount ready',
              style: const TextStyle(color: Color(0xffc3b5d1), fontSize: 12),
            ),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xff1c1727),
          border: Border.all(color: const Color(0xff9075b0)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            const _HudLabel('AUTO START IN'),
            const SizedBox(height: 4),
            Text(
              '${(_secondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
              key: const ValueKey('tacticalvoxelrpg-draft-countdown'),
              style: const TextStyle(
                fontFamily: 'Georgia',
                fontSize: 23,
                color: Color(0xffe2cef8),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget get _readyPlayerStatus {
    final readyIds = _readyIds;
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 7,
        runSpacing: 5,
        children: [
          for (final player in widget.ctx.lobby.players)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xff191522),
                border: Border.all(
                  color: readyIds.contains(player.id)
                      ? const Color(0xff8dc5a5)
                      : const Color(0xff51465f),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    readyIds.contains(player.id)
                        ? Icons.check_circle
                        : Icons.schedule,
                    size: 13,
                    color: readyIds.contains(player.id)
                        ? const Color(0xff8dc5a5)
                        : const Color(0xffa99ab7),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${player.nickname} · ${readyIds.contains(player.id) ? 'READY' : 'SELECTING'}',
                    style: const TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _roster(List<Map<String, Object?>> units, Set<String> selectedIds) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HudLabel('AVAILABLE HEROES'),
          const SizedBox(height: 9),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final unit in units)
                    _unitCard(unit, selectedIds.contains(unit['id'])),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _unitCard(Map<String, Object?> unit, bool selected) {
    final ready = _readyIds.contains(widget.ctx.myId);
    final portrait = _characterPortraitFor(unit);
    final hp = unit['hp'] as int;
    final maxHp = unit['maxHp'] as int;
    return SizedBox(
      width: 158,
      height: 235,
      child: Material(
        color: selected ? const Color(0xff30243e) : const Color(0xff181522),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: selected ? const Color(0xffd4b5f0) : const Color(0xff554968),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _inspectedUnitId = unit['id'] as String),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 82,
                  child: portrait == null
                      ? const Icon(Icons.person_outline, size: 48)
                      : Image.asset(
                          portrait,
                          package: 'nico_shared',
                          fit: BoxFit.contain,
                        ),
                ),
                Text(
                  (unit['role'] as String).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xffc8afe0),
                    fontSize: 7,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  unit['name'] as String,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Georgia', fontSize: 16),
                ),
                const SizedBox(height: 7),
                Text(
                  '$hp/$maxHp HP  ·  MOV ${unit['movement']}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xffc4b6d1), fontSize: 9),
                ),
                const Spacer(),
                OutlinedButton(
                  key: ValueKey('tacticalvoxelrpg-draft-select-${unit['id']}'),
                  onPressed: ready ? null : () => _toggleUnit(unit),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    side: BorderSide(
                      color: selected
                          ? const Color(0xffd4b5f0)
                          : const Color(0xff716183),
                    ),
                  ),
                  child: Text(selected ? 'IN COMPANY' : 'ADD TO COMPANY'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _unitDetails(Map<String, Object?>? unit) {
    if (unit == null) {
      return const _DraftPanel(
        child: Center(child: Text('Choose a hero to inspect their details.')),
      );
    }
    final deck = _deckFor(unit);
    final portrait = _characterPortraitFor(unit);
    return _DraftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (portrait != null)
                SizedBox(
                  width: 72,
                  height: 84,
                  child: Image.asset(
                    portrait,
                    package: 'nico_shared',
                    fit: BoxFit.contain,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HudLabel((unit['role'] as String).toUpperCase()),
                    const SizedBox(height: 4),
                    Text(
                      unit['name'] as String,
                      style: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 24,
                      ),
                    ),
                    Text(
                      unit['weapon'] as String,
                      style: const TextStyle(color: Color(0xffd0bcdf)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _DraftStat('HEALTH', '${unit['hp']}/${unit['maxHp']}'),
              _DraftStat('MOVEMENT', '${unit['movement']} tiles'),
              _DraftStat('MANA', '${unit['mana']}/${unit['maxMana']}'),
              _DraftStat(
                'WEAPON RANGE',
                '${unit['minimumRange']}–${unit['range']}',
              ),
              const _DraftStat('ACTION POINTS', '2 per activation'),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            children: [
              for (final tab in ['STATS', 'SUBDECK', 'DISCOVERED'])
                ChoiceChip(
                  label: Text(tab),
                  selected: _detailTab == tab,
                  onSelected: (_) => setState(() => _detailTab = tab),
                  selectedColor: const Color(0xff54416b),
                  backgroundColor: const Color(0xff211a2d),
                  labelStyle: const TextStyle(
                    color: Color(0xffe2d6ee),
                    fontSize: 9,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: _deckContent(unit, deck)),
        ],
      ),
    );
  }

  Widget _deckContent(
    Map<String, Object?> unit,
    List<Map<String, Object?>> deck,
  ) {
    if (_detailTab == 'STATS') {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          '${unit['name']} acts once each round. Their actions draw from a personal five-card hand. One card can be retained between rounds.',
          style: const TextStyle(color: Color(0xffc6b9d2), height: 1.5),
        ),
      );
    }
    if (deck.isEmpty) {
      return const Text('No cards have been discovered for this hero yet.');
    }
    return ListView(
      children: [
        Text(
          _detailTab == 'SUBDECK'
              ? 'PERSONAL SUBDECK · ${deck.fold<int>(0, (sum, card) => sum + (card['copies'] as int))} CARDS'
              : 'DISCOVERED CARDS · ${deck.length} TYPES',
          style: const TextStyle(
            color: Color(0xffcdb5e6),
            fontSize: 9,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 7),
        for (final card in deck)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Text(
              card['icon'] as String,
              style: const TextStyle(fontSize: 22, color: Color(0xffd6c3e8)),
            ),
            title: Text(card['name'] as String),
            subtitle: Text('${card['type']} · ${card['cost']} AP'),
            trailing: Text('×${card['copies']}'),
          ),
      ],
    );
  }

  Widget _readyFooter({
    required int selectedCount,
    required int readyCount,
    required int playerCount,
    required bool isReady,
  }) => Row(
    children: [
      Expanded(
        child: Text(
          '$selectedCount/$tacticalDraftUnitCount heroes selected  ·  $readyCount/$playerCount players ready',
          style: const TextStyle(color: Color(0xffc8b9d5), fontSize: 11),
        ),
      ),
      FilledButton.icon(
        key: const ValueKey('tacticalvoxelrpg-draft-ready'),
        onPressed: isReady || selectedCount == tacticalDraftUnitCount
            ? _toggleReady
            : null,
        icon: Icon(isReady ? Icons.edit_outlined : Icons.check_circle_outline),
        label: Text(isReady ? 'UNREADY' : 'READY'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xffc7a9e4),
          foregroundColor: const Color(0xff171220),
          disabledBackgroundColor: const Color(0xff30283b),
          disabledForegroundColor: const Color(0xff887a96),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
    ],
  );
}

class _DraftPanel extends StatelessWidget {
  const _DraftPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xdd1a1523),
      border: Border.all(color: const Color(0xff57476b)),
      borderRadius: BorderRadius.circular(10),
    ),
    padding: const EdgeInsets.all(14),
    child: child,
  );
}

class _DraftStat extends StatelessWidget {
  const _DraftStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xff211a2e),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xffa895bd),
            fontSize: 7,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 10)),
      ],
    ),
  );
}
