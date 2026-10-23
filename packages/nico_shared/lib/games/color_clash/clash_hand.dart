import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'clash_card.dart';
import 'clash_card_face.dart';

/// A player's hand as a fan of cards sized to the space it gets: as tall as
/// fits, overlapping just enough that the whole hand fits the width (it
/// scrolls sideways only when even a tight fan doesn't fit).
///
/// A playable card is played by tapping it or by dragging it up: it follows
/// the finger and is played when let go high enough or flicked up, and
/// springs back otherwise.
class ClashHand extends StatefulWidget {
  const ClashHand({
    super.key,
    required this.cards,
    required this.playable,
    required this.dimUnplayable,
    required this.onPlay,
    this.maxCardWidth = 150,
  });

  final List<ClashCard> cards;
  final Set<int> playable;

  /// Fades the cards that can't be played (on your turn).
  final bool dimUnplayable;

  /// Plays [card]; completes with false when the player backed out (such as
  /// closing a Wild's color picker), and the card springs back.
  final Future<bool> Function(ClashCard card) onPlay;
  final double maxCardWidth;

  /// How far up (in card heights) a card must be dragged to play it.
  static const playDistance = 0.45;

  /// Cards shrink to this width before the hand starts to scroll.
  static const minCardWidth = 60.0;

  @override
  State<ClashHand> createState() => _ClashHandState();
}

class _ClashHandState extends State<ClashHand>
    with SingleTickerProviderStateMixin {
  /// How much of each card stays visible in the tightest fan.
  static const _minOverlap = 0.3;

  /// Sideways room (in card widths) for the most tilted card in a fan.
  static const _tiltRoom = 0.2;

  int? _dragged;
  Offset _dragStart = Offset.zero;
  Offset _offset = Offset.zero;

  /// A card that was played and stays where it was let go until the hand
  /// update from the host removes it.
  int? _played;

  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => setState(() {}));
  Offset _backFrom = Offset.zero;
  int? _returning;
  Timer? _fallback;

  @override
  void didUpdateWidget(ClashHand old) {
    super.didUpdateWidget(old);
    if (_played != null && !widget.cards.any((c) => c.id == _played)) {
      _fallback?.cancel();
      _played = null;
      _offset = Offset.zero;
    }
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _back.dispose();
    super.dispose();
  }

  void _springBack(int id) {
    _backFrom = _offset;
    _returning = id;
    _dragged = null;
    _played = null;
    _offset = Offset.zero;
    _back.forward(from: 0);
  }

  Offset _offsetOf(int id) {
    if (id == _dragged || id == _played) return _offset;
    if (id == _returning && _back.isAnimating) {
      return _backFrom * (1 - Curves.easeOut.transform(_back.value));
    }
    return Offset.zero;
  }

  Future<void> _release(
    ClashCard card,
    double cardHeight,
    double velocity,
  ) async {
    final far = -_offset.dy > cardHeight * ClashHand.playDistance;
    final flicked = velocity < -900 && -_offset.dy > cardHeight * 0.15;
    if (!far && !flicked) {
      setState(() => _springBack(card.id));
      return;
    }
    setState(() {
      _dragged = null;
      _played = card.id;
    });
    final played = await widget.onPlay(card);
    if (!mounted || _played != card.id) return;
    if (!played) {
      setState(() => _springBack(card.id));
      return;
    }
    // Normally the next hand removes it; don't leave it floating otherwise.
    _fallback?.cancel();
    _fallback = Timer(const Duration(seconds: 2), () {
      if (mounted && _played == card.id) setState(() => _springBack(card.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = widget.cards;
        final n = cards.length;
        const side = 12.0;
        final width = constraints.maxWidth - 2 * side;
        // As tall as fits (leaving room for a playable card's lift), and
        // narrow enough for the tightest fan to fit, but never tiny: below
        // that the hand scrolls instead.
        final cardWidth = [
          widget.maxCardWidth,
          (constraints.maxHeight - 8) / 1.5 / 1.12,
          max(
            ClashHand.minCardWidth,
            width / (1 + 2 * _tiltRoom + _minOverlap * (n - 1)),
          ),
        ].reduce(min);
        final cardHeight = cardWidth * 1.5;
        final lift = cardHeight * 0.1;
        final gap = cardWidth * 0.08;
        final minStep = cardWidth * _minOverlap;
        // The tilted outer cards lean out by up to this much.
        final room = width - 2 * _tiltRoom * cardWidth;

        var step = cardWidth + gap;
        if (n > 1 && n * cardWidth + (n - 1) * gap > room) {
          step = (room - cardWidth) / (n - 1);
        }
        final scrolls = step < minStep;
        if (scrolls) step = minStep;
        final fanned = !scrolls && step < cardWidth;
        final total = n == 0 ? 0.0 : cardWidth + step * (n - 1);
        final left = scrolls ? side : side + (width - total) / 2;

        Widget positioned(int i) {
          final card = cards[i];
          final id = card.id;
          final canPlay = widget.playable.contains(id);
          final moving = id == _dragged || id == _played;
          final offset = _offsetOf(id);
          // A gentle arc when the cards overlap.
          final tilt = fanned && !moving && offset == Offset.zero
              ? (i - (n - 1) / 2) * min(0.03, 0.24 / n)
              : 0.0;
          Widget face = ClashCardFace(
            key: ValueKey('hand-card-$id'),
            card: card,
            width: cardWidth,
            onTap: canPlay ? () => widget.onPlay(card) : null,
          );
          if (canPlay) {
            face = GestureDetector(
              onVerticalDragStart: (d) => setState(() {
                _back.stop();
                _returning = null;
                _dragged = id;
                _dragStart = d.globalPosition;
                _offset = Offset.zero;
              }),
              onVerticalDragUpdate: (d) =>
                  setState(() => _offset = d.globalPosition - _dragStart),
              onVerticalDragEnd: (d) =>
                  _release(card, cardHeight, d.velocity.pixelsPerSecond.dy),
              onVerticalDragCancel: () => setState(() => _springBack(id)),
              child: face,
            );
          }
          return Positioned(
            key: ValueKey(id),
            left: left + step * i,
            top: lift + tilt.abs() * cardHeight * 0.5,
            child: Transform.translate(
              offset: offset + Offset(0, canPlay ? -lift : 0),
              child: Transform.rotate(
                angle: tilt,
                alignment: Alignment.bottomCenter,
                child: Transform.scale(
                  scale: moving ? 1.08 : 1,
                  child: Opacity(
                    opacity: widget.dimUnplayable && !canPlay ? 0.55 : 1,
                    child: face,
                  ),
                ),
              ),
            ),
          );
        }

        // The card being moved is painted last, over its neighbours.
        final order = [
          for (var i = 0; i < n; i++)
            if (!{_dragged, _played, _returning}.contains(cards[i].id)) i,
          for (var i = 0; i < n; i++)
            if ({_dragged, _played, _returning}.contains(cards[i].id)) i,
        ];
        final stack = SizedBox(
          width: scrolls ? total + 2 * side : constraints.maxWidth,
          height: constraints.maxHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [for (final i in order) positioned(i)],
          ),
        );
        return scrolls
            ? SingleChildScrollView(
                key: const ValueKey('hand-list'),
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: stack,
              )
            : KeyedSubtree(key: const ValueKey('hand-list'), child: stack);
      },
    );
  }
}
