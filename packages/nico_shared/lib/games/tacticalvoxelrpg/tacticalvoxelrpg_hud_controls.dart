part of 'tacticalvoxelrpg_view.dart';

extension _TacticalHudControls on _TacticalHud {
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
      if (active != null)
        TextButton.icon(
          key: const ValueKey('tacticalvoxelrpg-finish-unit'),
          onPressed: selectedCardId == null ? onFinish : null,
          icon: const Icon(Icons.check_circle_outline, size: 17),
          label: const Text('Finish unit'),
        ),
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
