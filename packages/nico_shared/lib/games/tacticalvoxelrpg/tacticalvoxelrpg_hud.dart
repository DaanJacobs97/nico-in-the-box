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
    required this.active,
    required this.hand,
    required this.selectedCardId,
    required this.mode,
    required this.handCollapsed,
    required this.onToggleHand,
    required this.canAct,
    required this.canEndTurn,
    required this.onInspectUnit,
    required this.onInspectCard,
    required this.onRetainCard,
    required this.onPan,
    required this.onFinish,
    required this.onEndTurn,
  });

  final List<Map<String, Object?>> units;
  final Map<String, Object?>? active;
  final List<Map<String, Object?>> hand;
  final int? selectedCardId;
  final String? mode;
  final bool handCollapsed;
  final VoidCallback onToggleHand;
  final bool canAct;
  final bool canEndTurn;
  final ValueChanged<Map<String, Object?>> onInspectUnit;
  final ValueChanged<Map<String, Object?>> onInspectCard;
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
              colors: [Color(0x0015101d), Color(0xe2141020), Color(0xf8120e1b)],
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
      if (active != null) ...[
        SizedBox(width: 190, child: _companyColumn(context, activeId)),
        const SizedBox(width: 22),
      ],
      Expanded(child: _handColumn(context)),
      const SizedBox(width: 22),
      SizedBox(width: 166, child: _turnControls(context)),
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
        SizedBox(
          height: handCollapsed ? 70 : 176,
          child: Row(
            children: [
              Expanded(
                child: handCollapsed
                    ? ClipRect(child: _handCards(context, compact: true))
                    : _handCards(context, compact: true),
              ),
              IconButton(
                key: const ValueKey('tacticalvoxelrpg-toggle-hand'),
                tooltip: handCollapsed
                    ? 'Show action hand'
                    : 'Hide action hand',
                onPressed: onToggleHand,
                icon: Icon(
                  handCollapsed ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xffd2b9ed),
                ),
              ),
            ],
          ),
        ),
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
      Expanded(child: _companyRow(context, activeId)),
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
            ? 'Drag a hero card onto the battlefield to activate it. Click to inspect.'
            : 'Finish this activation before playing another hero.',
        maxLines: 2,
        style: const TextStyle(color: Color(0xff8f9a8c), fontSize: 10),
      ),
    ],
  );

  Widget _companyRow(
    BuildContext context,
    Object? activeId, {
    bool compact = false,
  }) {
    final cards = [
      for (final unit in units)
        _UnitActivationCard(
          key: ValueKey('tacticalvoxelrpg-activate-${unit['id']}'),
          unit: unit,
          selected: unit['id'] == activeId,
          compact: compact,
          handCard: active == null,
          disabled:
              !canAct ||
              unit['completed'] == true ||
              activeId != null && unit['id'] != activeId,
          onTap: () => onInspectUnit(unit),
        ),
    ];
    if (compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [for (final card in cards) Expanded(child: card)],
      );
    }
    return Column(
      children: [
        for (final card in cards)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: card,
            ),
          ),
      ],
    );
  }

  Widget _handColumn(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _handHeader(context),
      const SizedBox(height: 3),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: handCollapsed && active != null
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        height: 70,
                        child: ClipRect(
                          child: _handCards(context, compact: false),
                        ),
                      ),
                    )
                  : _handCards(context, compact: false),
            ),
            if (active != null)
              SizedBox(
                width: 40,
                child: IconButton(
                  key: const ValueKey('tacticalvoxelrpg-toggle-hand'),
                  tooltip: handCollapsed
                      ? 'Show action hand'
                      : 'Hide action hand',
                  onPressed: onToggleHand,
                  icon: Icon(
                    handCollapsed ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xffd2b9ed),
                  ),
                ),
              ),
          ],
        ),
      ),
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
      return _unitActivationHand(compact: compact);
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
                  targeting: selectedCardId != null,
                  disabled:
                      !canAct ||
                      (active!['energy'] as int) < (hand[i]['cost'] as int) ||
                      selectedCardId != null ||
                      hand[i]['kind'] == 'skill' &&
                          (active!['mana'] as int) < 1,
                  onTap: () => onInspectCard(hand[i]),
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
      if (active != null) ...[_retainPouch(context), const SizedBox(height: 7)],
      if (active != null) ...[
        TextButton.icon(
          key: const ValueKey('tacticalvoxelrpg-finish-unit'),
          onPressed: selectedCardId == null ? onFinish : null,
          icon: const Icon(Icons.check_circle_outline, size: 17),
          label: const Text('Finish unit'),
        ),
      ],
      FilledButton.icon(
        key: const ValueKey('tacticalvoxelrpg-end-turn'),
        onPressed: canAct && canEndTurn ? onEndTurn : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xffbfa5df),
          foregroundColor: const Color(0xff181322),
          disabledBackgroundColor: const Color(0xff30283b),
          disabledForegroundColor: const Color(0xffa99ab7),
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
        onPressed: selectedCardId == null ? onPan : null,
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

  Widget _retainPouch(BuildContext context) {
    final retainedId = active?['retainedCardId'];
    final retained = hand.where((card) => card['id'] == retainedId).firstOrNull;
    return DragTarget<_TacticalDragPayload>(
      key: const ValueKey('tacticalvoxelrpg-retain-pouch'),
      onWillAcceptWithDetails: (details) =>
          selectedCardId == null &&
          details.data.cardId != null &&
          details.data.unitId == active?['id'],
      onAcceptWithDetails: (details) => onRetainCard(details.data.cardId!),
      builder: (context, candidates, rejected) => OutlinedButton(
        onPressed: active == null || selectedCardId != null
            ? null
            : () => _showRetainPicker(context),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: const Color(0xff21182d),
          side: BorderSide(
            color: candidates.isNotEmpty
                ? const Color(0xffd4b9f0)
                : const Color(0xff79668d),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          children: [
            Icon(
              retained == null ? Icons.inbox_outlined : Icons.inbox,
              size: 21,
              color: const Color(0xffd2b9ed),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RETAIN ${retained == null ? '0/1' : '1/1'}',
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 1,
                      color: Color(0xffd8c6e8),
                    ),
                  ),
                  Text(
                    retained?['name'] as String? ??
                        (candidates.isNotEmpty
                            ? 'Drop to retain'
                            : 'Choose a card'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xffa89ab8),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRetainPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff1b1525),
        title: Text('${active!['name']} · retain pouch'),
        content: SizedBox(
          width: 330,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final card in hand)
                ListTile(
                  leading: Text(
                    card['icon'] as String,
                    style: const TextStyle(
                      fontSize: 23,
                      color: Color(0xffd2b9ed),
                    ),
                  ),
                  title: Text(card['name'] as String),
                  subtitle: Text('${card['cost']} AP · ${card['type']}'),
                  trailing: card['id'] == active!['retainedCardId']
                      ? const Icon(Icons.check, color: Color(0xffd2b9ed))
                      : null,
                  onTap: () {
                    onRetainCard(card['id']! as int);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pileButton(
    BuildContext context,
    String label,
    Object? pile,
    int count,
  ) => TextButton(
    onPressed: count == 0 || selectedCardId != null
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
        onPressed: selectedCardId == null ? onPan : null,
        icon: const Icon(Icons.pan_tool_alt, size: 15),
        label: Text(mode == 'pan' ? 'Stop panning' : 'Pan'),
      ),
      if (active != null)
        TextButton(
          key: const ValueKey('tacticalvoxelrpg-finish-unit'),
          onPressed: selectedCardId == null ? onFinish : null,
          child: const Text('Finish unit'),
        ),
      if (active != null)
        TextButton.icon(
          onPressed: selectedCardId == null
              ? () => _showRetainPicker(context)
              : null,
          icon: const Icon(Icons.inbox_outlined, size: 15),
          label: Text(
            'Retain ${active!['retainedCardId'] == null ? '0/1' : '1/1'}',
          ),
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
      backgroundColor: const Color(0xff171220),
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
