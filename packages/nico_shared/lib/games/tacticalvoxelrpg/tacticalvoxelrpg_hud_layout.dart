part of 'tacticalvoxelrpg_view.dart';

extension _TacticalHudLayout on _TacticalHud {
  Widget _handViewport(BuildContext context, {required bool compact}) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final fullHeight = compact ? 172.0 : 246.0;
          final desiredHeight = handCollapsed ? 70.0 : fullHeight;
          final viewportHeight = min(desiredHeight, constraints.maxHeight);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: viewportHeight,
            alignment: Alignment.bottomCenter,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: fullHeight,
                maxHeight: fullHeight,
                child: _handCards(context, compact: compact),
              ),
            ),
          );
        },
      );
}
