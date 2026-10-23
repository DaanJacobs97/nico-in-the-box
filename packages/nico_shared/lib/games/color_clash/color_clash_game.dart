import 'dart:math';

import '../../net/protocol.dart';
import '../game_session.dart';
import 'clash_card.dart';

const colorClashDefinition = GameDefinition(
  id: 'colorclash',
  name: 'Color Clash',
  description: 'Match colors and numbers, empty your hand first.',
  minPlayers: 2,
  maxPlayers: 4,
  options: [
    GameOption(
      id: 'stacking',
      label: 'Stack +2 and +4',
      description:
          'Answer a +2 with a +2, or any draw with a Wild +4; the next player '
          'draws the total.',
      defaultValue: true,
    ),
    GameOption(
      id: 'playAfterPenalty',
      label: 'Play after drawing a penalty',
      description: 'Off: drawing +2 or +4 also skips your turn.',
      defaultValue: true,
    ),
  ],
  createSession: _create,
);

GameSession _create(
  List<PlayerInfo> players,
  int round,
  Random random,
  GameOptions options,
) => ColorClashSession(
  players,
  random: random,
  round: round,
  stacking: options['stacking'] ?? true,
  playAfterPenalty: options['playAfterPenalty'] ?? true,
);

const handSize = 7;
const lastCardPenalty = 2;

/// Uno-style card game, core rules.
///
/// Actions:
/// - `{'type': 'play', 'cardId': int, 'color'?: 'red'|'yellow'|'green'|'blue'}`
///   (`color` is required for Wild cards)
/// - `{'type': 'draw'}` draws one card. If it can be played the player may
///   play it or `pass`; otherwise the turn ends. With a penalty pending it
///   draws the whole penalty instead.
/// - `{'type': 'pass'}` only after drawing a playable card.
/// - `{'type': 'callLast'}` when holding one card, or two on your turn.
/// - `{'type': 'catch'}` makes a player who reached one card without calling
///   draw [lastCardPenalty]. Possible until the next play or draw.
///
/// With [stacking], a +2 or +4 becomes a pending penalty the next player
/// either stacks on (+2 on a +2, a Wild +4 on either) or draws in full. With
/// [playAfterPenalty], drawing a penalty doesn't cost the turn. No Wild Draw
/// Four challenges. Reverse acts as Skip with two players. The starting
/// player rotates every round.
class ColorClashSession implements GameSession {
  ColorClashSession(
    List<PlayerInfo> players, {
    required Random random,
    int round = 0,
    this.stacking = false,
    this.playAfterPenalty = false,
  }) : _players = players,
       _random = random,
       _turnIndex = round % players.length {
    _drawPile.addAll(buildDeck()..shuffle(random));
    for (final p in players) {
      _hands[p.id] = [];
    }
    for (var i = 0; i < handSize; i++) {
      for (final p in players) {
        _hands[p.id]!.add(_drawPile.removeLast());
      }
    }
    // Start on a number card so no opening effect needs resolving.
    while (_drawPile.last.kind != CardKind.number) {
      _drawPile.insert(0, _drawPile.removeLast());
    }
    final first = _drawPile.removeLast();
    _discard.add(first);
    _color = first.color;
    _log.add('First card: $first');
  }

  /// Builds a session in an exact state. Intended for tests.
  ColorClashSession.custom(
    List<PlayerInfo> players, {
    required Map<String, List<ClashCard>> hands,
    required List<ClashCard> drawPile,
    required List<ClashCard> discard,
    CardColor? color,
    this._turnIndex = 0,
    Random? random,
    this.stacking = false,
    this.playAfterPenalty = false,
  }) : _players = players,
       _random = random ?? Random(0) {
    for (final p in players) {
      _hands[p.id] = List.of(hands[p.id] ?? const []);
    }
    _drawPile.addAll(drawPile);
    _discard.addAll(discard);
    _color = color ?? discard.last.color;
  }

  /// The "Stack +2 and +4" option.
  final bool stacking;

  /// The "Play after drawing a penalty" option.
  final bool playAfterPenalty;

  /// Cards the current player must draw unless they stack (with [stacking]).
  int _penalty = 0;

  final List<PlayerInfo> _players;
  final Random _random;
  final Map<String, List<ClashCard>> _hands = {};

  /// Top of each pile is the last element.
  final List<ClashCard> _drawPile = [];
  final List<ClashCard> _discard = [];

  late CardColor _color;
  int _turnIndex;
  int _direction = 1;

  /// Card the current player just drew and may still play.
  int? _pendingDrawnId;
  final Set<String> _calledLast = {};

  /// Player who reached one card without calling and can be caught.
  String? _vulnerable;
  String? _winner;
  final List<String> _log = [];

  String get _currentId => _players[_turnIndex].id;
  ClashCard get _top => _discard.last;

  String _name(String id) => _players.firstWhere((p) => p.id == id).nickname;

  void _addLog(String entry) {
    _log.add(entry);
    if (_log.length > 6) _log.removeAt(0);
  }

  int _indexAfter(int steps) {
    final n = _players.length;
    return ((_turnIndex + _direction * steps) % n + n) % n;
  }

  void _advance([int steps = 1]) => _turnIndex = _indexAfter(steps);

  /// Draws up to [count] cards, reshuffling the discard pile (minus its top
  /// card) when the draw pile runs out. Returns the cards drawn.
  List<ClashCard> _draw(String playerId, int count) {
    final drawn = <ClashCard>[];
    for (var i = 0; i < count; i++) {
      if (_drawPile.isEmpty) {
        if (_discard.length <= 1) break;
        final top = _discard.removeLast();
        _drawPile.addAll(_discard..shuffle(_random));
        _discard
          ..clear()
          ..add(top);
        _addLog('Discard pile reshuffled');
      }
      drawn.add(_drawPile.removeLast());
    }
    final hand = _hands[playerId]!..addAll(drawn);
    if (hand.length > 1) _calledLast.remove(playerId);
    return drawn;
  }

  bool _canPlay(ClashCard card) {
    if (_penalty == 0) return card.canPlayOn(_top, _color);
    // A pending penalty can only be answered by stacking on it.
    return card.kind == CardKind.wildDrawFour ||
        (card.kind == CardKind.drawTwo && _top.kind == CardKind.drawTwo);
  }

  @override
  bool get isOver => _winner != null;

  @override
  void applyAction(String playerId, Json action) {
    if (!_hands.containsKey(playerId)) {
      throw const GameActionException('You are not playing this game.');
    }
    if (isOver) throw const GameActionException('The round is over.');

    switch (action['type']) {
      case 'callLast':
        _callLast(playerId);
      case 'catch':
        _catch(playerId);
      case 'play':
        _requireTurn(playerId);
        _play(playerId, action);
      case 'draw':
        _requireTurn(playerId);
        _drawForTurn(playerId);
      case 'pass':
        _requireTurn(playerId);
        if (_pendingDrawnId == null) {
          throw const GameActionException('You can only pass after drawing.');
        }
        _pendingDrawnId = null;
        _addLog('${_name(playerId)} passed');
        _advance();
      default:
        throw const GameActionException('Unknown move.');
    }
  }

  void _requireTurn(String playerId) {
    if (playerId != _currentId) {
      throw const GameActionException("It's not your turn.");
    }
  }

  bool _canCallLast(String playerId) {
    if (_calledLast.contains(playerId)) return false;
    final count = _hands[playerId]!.length;
    return count == 1 ||
        (count == 2 && playerId == _currentId && _pendingDrawnId == null);
  }

  void _callLast(String playerId) {
    if (!_canCallLast(playerId)) {
      throw const GameActionException(
        'You can call "Last card!" with one card, or two on your turn.',
      );
    }
    _calledLast.add(playerId);
    if (_vulnerable == playerId) _vulnerable = null;
    _addLog('${_name(playerId)}: Last card!');
  }

  void _catch(String playerId) {
    final target = _vulnerable;
    if (target == null || target == playerId) {
      throw const GameActionException('There is nobody to catch.');
    }
    _vulnerable = null;
    _draw(target, lastCardPenalty);
    _addLog(
      '${_name(playerId)} caught ${_name(target)}: +$lastCardPenalty cards',
    );
  }

  void _play(String playerId, Json action) {
    final hand = _hands[playerId]!;
    final cardId = action['cardId'];
    final card = hand.where((c) => c.id == cardId).firstOrNull;
    if (card == null) {
      throw const GameActionException("You don't have that card.");
    }
    if (_pendingDrawnId != null && card.id != _pendingDrawnId) {
      throw const GameActionException('Play the card you just drew, or pass.');
    }
    if (!_canPlay(card)) {
      throw GameActionException("$card can't be played on $_top.");
    }
    CardColor? chosen;
    if (card.isWild) {
      final colorName = action['color'];
      chosen = playableColors.where((c) => c.name == colorName).firstOrNull;
      if (chosen == null) {
        throw const GameActionException('Pick a color for your Wild card.');
      }
    }

    // Any play closes the window for catching the previous player.
    _vulnerable = null;
    _pendingDrawnId = null;
    hand.remove(card);
    _discard.add(card);
    _color = chosen ?? card.color;
    _addLog(
      '${_name(playerId)} played $card'
      '${chosen != null ? ' (${chosen.name})' : ''}',
    );

    if (hand.isEmpty) {
      _winner = playerId;
      _addLog('${_name(playerId)} wins the round!');
      return;
    }
    if (hand.length == 1 && !_calledLast.contains(playerId)) {
      _vulnerable = playerId;
    }

    switch (card.kind) {
      case CardKind.number:
      case CardKind.wild:
        _advance();
      case CardKind.skip:
        _advance(2);
      case CardKind.reverse:
        if (_players.length == 2) {
          _advance(2);
        } else {
          _direction = -_direction;
          _advance();
        }
      case CardKind.drawTwo:
        _penalize(2);
      case CardKind.wildDrawFour:
        _penalize(4);
    }
  }

  /// The next player draws [count] cards, or with [stacking] faces a pending
  /// penalty they can stack on. Without [playAfterPenalty] drawing also costs
  /// them their turn.
  void _penalize(int count) {
    if (stacking) {
      _penalty += count;
      _advance();
      _addLog('${_name(_currentId)} must draw $_penalty or stack');
      return;
    }
    final victim = _players[_indexAfter(1)].id;
    final drawn = _draw(victim, count);
    if (playAfterPenalty) {
      _addLog('${_name(victim)} draws ${drawn.length}');
      _advance();
    } else {
      _addLog('${_name(victim)} draws ${drawn.length} and is skipped');
      _advance(2);
    }
  }

  void _drawForTurn(String playerId) {
    if (_pendingDrawnId != null) {
      throw const GameActionException('Play the card you drew, or pass.');
    }
    _vulnerable = null;
    if (_penalty > 0) {
      final drawn = _draw(playerId, _penalty);
      _penalty = 0;
      if (playAfterPenalty) {
        _addLog('${_name(playerId)} draws ${drawn.length}');
      } else {
        _addLog('${_name(playerId)} draws ${drawn.length} and is skipped');
        _advance();
      }
      return;
    }
    final drawn = _draw(playerId, 1);
    if (drawn.isEmpty) {
      _addLog('${_name(playerId)} could not draw and passes');
      _advance();
    } else if (_canPlay(drawn.single)) {
      _pendingDrawnId = drawn.single.id;
      _addLog('${_name(playerId)} drew a card');
    } else {
      _addLog('${_name(playerId)} drew a card and passes');
      _advance();
    }
  }

  List<ClashCard> _sorted(List<ClashCard> hand) => List.of(hand)
    ..sort((a, b) {
      final byColor = a.color.index.compareTo(b.color.index);
      if (byColor != 0) return byColor;
      final byKind = a.kind.index.compareTo(b.kind.index);
      if (byKind != 0) return byKind;
      return (a.value ?? 0).compareTo(b.value ?? 0);
    });

  /// Public state for a shared screen: card counts, never cards.
  @override
  Json tableView() => {
    'players': [
      for (final p in _players)
        {
          'id': p.id,
          'cards': _hands[p.id]!.length,
          'calledLast': _calledLast.contains(p.id),
        },
    ],
    'turn': isOver ? null : _currentId,
    'direction': _direction,
    'top': _top.toJson(),
    'color': _color.name,
    'drawPile': _drawPile.length,
    'penalty': _penalty,
    'vulnerable': _vulnerable,
    'winner': _winner,
    'log': List.of(_log),
  };

  /// The table view plus what only [playerId] may see: their hand and the
  /// moves available to them.
  @override
  Json viewFor(String playerId) {
    final hand = _hands[playerId] ?? const [];
    final myTurn = playerId == _currentId && !isOver;
    return {
      ...tableView(),
      'hand': [for (final c in _sorted(hand)) c.toJson()],
      'pendingDrawn': myTurn ? _pendingDrawnId : null,
      'playable': [
        if (myTurn)
          for (final c in hand)
            if (_canPlay(c) &&
                (_pendingDrawnId == null || c.id == _pendingDrawnId))
              c.id,
      ],
      'canCallLast': _hands.containsKey(playerId) && _canCallLast(playerId),
    };
  }

  @override
  Json? get result => _winner == null
      ? null
      : {
          'winnerIds': [_winner],
          'summary': '${_name(_winner!)} wins the round!',
        };
}
