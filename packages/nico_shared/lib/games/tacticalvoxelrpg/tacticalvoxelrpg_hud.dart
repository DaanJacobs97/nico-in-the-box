part of 'tacticalvoxelrpg_view.dart';

class _TacticalDragPayload {
  const _TacticalDragPayload.unit(this.unitId) : cardId = null;
  const _TacticalDragPayload.card(this.unitId, this.cardId);

  final String unitId;
  final int? cardId;
}

class _TacticalHud extends StatelessWidget {
  const _TacticalHud({
    required this.units,
    required this.ownerId,
    required this.active,
    required this.hand,
    required this.selectedCardId,
    required this.mode,
    required this.canAct,
    required this.canEndTurn,
    required this.onActivate,
    required this.onSelectCard,
    required this.onRetainCard,
    required this.onPan,
    required this.onFinish,
    required this.onEndTurn,
  });

  final List<Map<String, Object?>> units;
  final String ownerId;
  final Map<String, Object?>? active;
  final List<Map<String, Object?>> hand;
  final int? selectedCardId;
  final String? mode;
  final bool canAct;
  final bool canEndTurn;
  final ValueChanged<String> onActivate;
  final ValueChanged<Map<String, Object?>> onSelectCard;
  final ValueChanged<int> onRetainCard;
  final VoidCallback onPan;
  final VoidCallback onFinish;
  final VoidCallback onEndTurn;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 900;
      final activeId = active?['id'];
      final height = min(compact ? 400.0 : 340.0, constraints.maxHeight);
      return SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00101513), Color(0xc90d1311), Color(0xf20d1311)],
              stops: [0, 0.13, 0.52],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 28,
              compact ? 8 : 24,
              compact ? 10 : 28,
              compact ? 6 : 12,
            ),
            child: compact
                ? _compactLayout(context, activeId)
                : _wideLayout(context, activeId),
          ),
        ),
      );
    },
  );

  Widget _wideLayout(BuildContext context, Object? activeId) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      SizedBox(width: 190, child: _companyColumn(context, activeId)),
      const SizedBox(width: 22),
      Expanded(child: _handColumn(context)),
      const SizedBox(width: 22),
      SizedBox(width: 155, child: _turnControls(context)),
    ],
  );

  Widget _compactLayout(BuildContext context, Object? activeId) => Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      SizedBox(
        height: 92,
        child: _companyRow(context, activeId, compact: true),
      ),
      if (active != null) ...[
        const SizedBox(height: 4),
        SizedBox(height: 176, child: _handCards(context, compact: true)),
      ],
      const SizedBox(height: 4),
      _compactControls(context),
    ],
  );

  Widget _companyColumn(BuildContext context, Object? activeId) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _HudLabel('YOUR COMPANY'),
      const SizedBox(height: 7),
      _companyRow(context, activeId),
      const Spacer(),
      Text(
        active == null ? 'SELECT A UNIT' : 'UNIT COMMITTED',
        style: const TextStyle(
          color: Color(0xffc0ac7e),
          fontSize: 9,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        active == null
            ? 'Choose a hero to begin their activation.'
            : 'Finish this activation before changing heroes.',
        maxLines: 2,
        style: const TextStyle(color: Color(0xff8f9a8c), fontSize: 10),
      ),
    ],
  );

  Widget _companyRow(
    BuildContext context,
    Object? activeId, {
    bool compact = false,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      for (final unit in units.where((unit) => unit['owner'] == ownerId))
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _UnitActivationCard(
              key: ValueKey('tacticalvoxelrpg-activate-${unit['id']}'),
              unit: unit,
              selected: unit['id'] == activeId,
              compact: compact,
              disabled:
                  !canAct ||
                  unit['completed'] == true ||
                  activeId != null && unit['id'] != activeId,
              onTap: () => onActivate(unit['id']! as String),
            ),
          ),
        ),
    ],
  );

  Widget _handColumn(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _handHeader(context),
      const SizedBox(height: 3),
      Expanded(child: _handCards(context, compact: false)),
    ],
  );

  Widget _handHeader(BuildContext context) {
    final ap = active?['energy'] as int? ?? 0;
    final maxAp = active?['maxEnergy'] as int? ?? 2;
    return Row(
      children: [
        Expanded(
          child: Text(
            active == null ? 'Play a unit' : '${active!['name']}’s hand',
            style: const TextStyle(fontFamily: 'Georgia', fontSize: 16),
          ),
        ),
        if (active != null) ...[
          for (var i = 0; i < maxAp; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.rotate(
                angle: pi / 4,
                child: Container(
                  width: 9,
                  height: 9,
                  color: i < ap
                      ? const Color(0xffccb27b)
                      : const Color(0xff40483d),
                ),
              ),
            ),
          const SizedBox(width: 6),
          Text(
            '$ap/$maxAp AP',
            style: const TextStyle(color: Color(0xffd6bd84), fontSize: 10),
          ),
          const SizedBox(width: 15),
          Text(
            '${active!['drawCount']} DRAW · ${active!['discardCount']} DISCARD',
            style: const TextStyle(color: Color(0xff9ca791), fontSize: 9),
          ),
        ] else
          const Text(
            'CHOOSE YOUR NEXT ACTIVATION',
            style: TextStyle(color: Color(0xffc0ac7e), fontSize: 9),
          ),
      ],
    );
  }

  Widget _handCards(BuildContext context, {required bool compact}) {
    if (active == null) {
      return const Center(
        child: Text(
          'Activate a hero to reveal their action hand',
          style: TextStyle(color: Color(0xff899386), fontSize: 11),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const cardWidth = 145.0;
        final gap = constraints.maxWidth >= cardWidth * hand.length ? 3.0 : 0.0;
        final cards = AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Row(
            key: ValueKey(
              '${active!['id']}:${hand.map((card) => card['id']).join(',')}',
            ),
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < hand.length; i++)
                _TacticalHandCard(
                  key: ValueKey('tacticalvoxelrpg-card-${hand[i]['id']}'),
                  unitId: active!['id']! as String,
                  card: hand[i],
                  movement: active!['movement'] as int,
                  compact: compact,
                  selected: hand[i]['id'] == selectedCardId,
                  retained: hand[i]['id'] == active!['retainedCardId'],
                  index: i,
                  disabled:
                      !canAct ||
                      (active!['energy'] as int) < (hand[i]['cost'] as int) ||
                      hand[i]['kind'] == 'skill' &&
                          (active!['mana'] as int) < 1,
                  onTap: () => onSelectCard(hand[i]),
                  onDragStarted: () => onSelectCard(hand[i]),
                  onRetain: () => onRetainCard(hand[i]['id']! as int),
                ),
            ],
          ),
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gap),
              child: cards,
            ),
          ),
        );
      },
    );
  }

  Widget _turnControls(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (active != null)
        Row(
          children: [
            Expanded(
              child: _pileButton(
                context,
                'Draw',
                active!['drawPile'],
                active!['drawCount'] as int? ?? 0,
              ),
            ),
            Expanded(
              child: _pileButton(
                context,
                'Discard',
                active!['discardPile'],
                active!['discardCount'] as int? ?? 0,
              ),
            ),
          ],
        ),
      const Spacer(),
      if (active != null) ...[
        TextButton.icon(
          key: const ValueKey('tacticalvoxelrpg-finish-unit'),
          onPressed: onFinish,
          icon: const Icon(Icons.check_circle_outline, size: 17),
          label: const Text('Finish unit'),
        ),
      ],
      FilledButton.icon(
        key: const ValueKey('tacticalvoxelrpg-end-turn'),
        onPressed: canAct && canEndTurn ? onEndTurn : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xffbda777),
          foregroundColor: const Color(0xff151b16),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
        ),
        icon: const Icon(Icons.skip_next, size: 17),
        label: Text(
          active == null ? 'END ROUND' : 'END TURN',
          style: const TextStyle(fontSize: 10, letterSpacing: 1),
        ),
      ),
      const SizedBox(height: 9),
      OutlinedButton.icon(
        key: const ValueKey('tacticalvoxelrpg-pan-map'),
        onPressed: onPan,
        icon: const Icon(Icons.pan_tool_alt, size: 15),
        label: Text(mode == 'pan' ? 'Stop panning' : 'Pan map'),
      ),
      if (active == null)
        const Text(
          '2 ACTION POINTS PER UNIT / TURN',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xff6e7c6c), fontSize: 8),
        ),
    ],
  );

  Widget _pileButton(
    BuildContext context,
    String label,
    Object? pile,
    int count,
  ) => TextButton(
    onPressed: count == 0
        ? null
        : () => showDialog<void>(
            context: context,
            builder: (context) => _TacticalPileDialog(
              title: '${active!['name']} · $label pile',
              cards: _objects(pile),
            ),
          ),
    child: Text('$label · $count', style: const TextStyle(fontSize: 9)),
  );

  Widget _compactControls(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 5,
    runSpacing: 3,
    children: [
      OutlinedButton.icon(
        key: const ValueKey('tacticalvoxelrpg-pan-map'),
        onPressed: onPan,
        icon: const Icon(Icons.pan_tool_alt, size: 15),
        label: Text(mode == 'pan' ? 'Stop panning' : 'Pan'),
      ),
      if (active != null)
        TextButton(
          key: const ValueKey('tacticalvoxelrpg-finish-unit'),
          onPressed: onFinish,
          child: const Text('Finish unit'),
        ),
      FilledButton(
        key: const ValueKey('tacticalvoxelrpg-end-turn'),
        onPressed: canAct && canEndTurn ? onEndTurn : null,
        child: const Text('End turn'),
      ),
    ],
  );
}

class _TacticalPileDialog extends StatelessWidget {
  const _TacticalPileDialog({required this.title, required this.cards});

  final String title;
  final List<Map<String, Object?>> cards;

  @override
  Widget build(BuildContext context) {
    final sorted = [...cards]
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return AlertDialog(
      backgroundColor: const Color(0xff19221c),
      title: Text(title, style: const TextStyle(fontFamily: 'Georgia')),
      content: SizedBox(
        width: 360,
        child: sorted.isEmpty
            ? const Text('This pile is empty.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  final card = sorted[index];
                  return ListTile(
                    leading: Text(
                      card['icon'] as String,
                      style: const TextStyle(fontSize: 22),
                    ),
                    title: Text(card['name'] as String),
                    subtitle: Text('${card['type']} · ${card['cost']} AP'),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
