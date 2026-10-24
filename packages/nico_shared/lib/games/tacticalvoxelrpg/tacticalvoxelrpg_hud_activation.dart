part of 'tacticalvoxelrpg_view.dart';

extension _TacticalUnitActivationHand on _TacticalHud {
  Widget _unitActivationHand({required bool compact}) => units.isEmpty
      ? const Center(
          child: Text(
            'No hero cards were received for this player.',
            style: TextStyle(color: Color(0xffffa3a3), fontSize: 12),
          ),
        )
      : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final unit in units)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _UnitActivationCard(
                  key: ValueKey('tacticalvoxelrpg-activate-${unit['id']}'),
                  unit: unit,
                  selected: false,
                  compact: compact,
                  handCard: !compact,
                  disabled: !canAct || unit['completed'] == true,
                  onTap: () => onInspectUnit(unit),
                ),
              ),
          ],
        );
}
