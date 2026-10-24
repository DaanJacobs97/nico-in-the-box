part of 'tacticalvoxelrpg_view.dart';

class _TacticalSelectionTable extends StatelessWidget {
  const _TacticalSelectionTable({required this.ctx});

  final TableContext ctx;

  @override
  Widget build(BuildContext context) {
    final table = ctx.table;
    final ready = table['draftReadyCount'] as int? ?? 0;
    final players = table['draftPlayerCount'] as int? ?? 1;
    final seconds = table['draftSeconds'] as int? ?? 60;
    return Container(
      color: const Color(0xff100d18),
      alignment: Alignment.center,
      child: _DraftPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ASHEN OATH',
              style: TextStyle(
                fontFamily: 'Georgia',
                letterSpacing: 5,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 14),
            const _HudLabel('COMPANY SELECTION'),
            const SizedBox(height: 8),
            Text('$ready of $players players ready'),
            const SizedBox(height: 6),
            Text('Battle begins in ${seconds}s'),
          ],
        ),
      ),
    );
  }
}
