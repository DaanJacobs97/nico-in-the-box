part of 'tacticalvoxelrpg_game.dart';

enum TacticalCardKind { move, attack, trap, overwatch, skill }

extension TacticalCardDetails on TacticalCardKind {
  String get title => switch (this) {
    TacticalCardKind.move => 'Strides',
    TacticalCardKind.attack => 'Weapon strike',
    TacticalCardKind.trap => 'Thorn snare',
    TacticalCardKind.overwatch => 'Vigil',
    TacticalCardKind.skill => 'Soul rend',
  };

  String get type => switch (this) {
    TacticalCardKind.move => 'MOVEMENT',
    TacticalCardKind.attack => 'ATTACK',
    TacticalCardKind.trap => 'TRAP',
    TacticalCardKind.overwatch => 'REACTION',
    TacticalCardKind.skill => 'SPECIAL',
  };

  String get icon => switch (this) {
    TacticalCardKind.move => '↟',
    TacticalCardKind.attack => '⚔',
    TacticalCardKind.trap => '♧',
    TacticalCardKind.overwatch => '◉',
    TacticalCardKind.skill => '✧',
  };

  String get description => switch (this) {
    TacticalCardKind.move => 'Move up to {mov} tiles.',
    TacticalCardKind.attack => 'Deal 8 damage. Weapon range.',
    TacticalCardKind.trap => 'Place a snare. 6 damage on entry.',
    TacticalCardKind.overwatch =>
      'Strike the next moving enemy in weapon range.',
    TacticalCardKind.skill => 'Deal 14 damage. Range 1–4. Costs 1 mana.',
  };

  int get cost => this == TacticalCardKind.skill ? 2 : 1;
}

class TacticalCard {
  const TacticalCard({required this.id, required this.kind});

  final int id;
  final TacticalCardKind kind;

  Json toJson() => {
    'id': id,
    'kind': kind.name,
    'name': kind.title,
    'type': kind.type,
    'icon': kind.icon,
    'cost': kind.cost,
    'text': kind.description,
  };
}

extension _TacticalCardCombat on TacticalVoxelRPGSession {
  void _initializeCards(TacticalUnit unit) {
    if (unit.hand.isNotEmpty || unit.drawPile.isNotEmpty) return;
    const deck = [
      TacticalCardKind.move,
      TacticalCardKind.attack,
      TacticalCardKind.trap,
      TacticalCardKind.move,
      TacticalCardKind.attack,
      TacticalCardKind.overwatch,
      TacticalCardKind.skill,
      TacticalCardKind.attack,
      TacticalCardKind.move,
      TacticalCardKind.trap,
    ];
    unit.drawPile.addAll([
      for (var i = 0; i < deck.length; i++) TacticalCard(id: i, kind: deck[i]),
    ]);
    unit.drawPile.shuffle(_random);
    _drawCards(unit);
  }

  void _drawCards(TacticalUnit unit) {
    while (unit.hand.length < 5) {
      if (unit.drawPile.isEmpty) {
        if (unit.discardPile.isEmpty) break;
        unit.drawPile.addAll(unit.discardPile);
        unit.discardPile.clear();
        unit.drawPile.shuffle(_random);
      }
      unit.hand.add(unit.drawPile.removeLast());
    }
  }

  void _prepareCardsForNextTurn(TacticalUnit unit) {
    final retainedId = unit.retainedCardId;
    final retained = unit.hand.where((card) => card.id == retainedId).toList();
    unit.discardPile.addAll(unit.hand.where((card) => card.id != retainedId));
    unit
      ..hand = retained
      ..retainedCardId = null;
  }

  void _retainCard(String playerId, Json action) {
    final unit = _actionUnit(playerId, action);
    final cardId = action['cardId'];
    if (cardId is! int || !unit.hand.any((card) => card.id == cardId)) {
      throw const GameActionException(
        'Choose a card in the active unit’s hand.',
      );
    }
    unit.retainedCardId = unit.retainedCardId == cardId ? null : cardId;
    _recordLastAction({
      'type': 'retain',
      'unit': unit.id,
      'cardId': unit.retainedCardId,
    });
  }

  void _finishUnit(String playerId, Json action) {
    final unit = _actionUnit(playerId, action);
    unit
      ..completed = true
      ..route = [];
    _selectedUnitId = null;
    _recordLastAction({
      'type': 'finishUnit',
      'unit': unit.id,
      'x': unit.x,
      'y': unit.y,
    });
  }

  void _playCard(String playerId, Json action) {
    final unit = _actionUnit(playerId, action);
    final cardId = action['cardId'];
    final card = cardId is int
        ? unit.hand.where((entry) => entry.id == cardId).firstOrNull
        : null;
    if (card == null) {
      throw const GameActionException(
        'Choose a card in the active unit’s hand.',
      );
    }
    if (unit.energy < card.kind.cost) {
      throw const GameActionException(
        'Not enough action points for that card.',
      );
    }
    if (card.kind == TacticalCardKind.skill && unit.mana < 1) {
      throw const GameActionException('Not enough mana for Soul rend.');
    }

    TacticalUnit? target;
    GridPoint? targetPoint;
    List<GridPoint> route = [];
    switch (card.kind) {
      case TacticalCardKind.move:
        final path =
            action['path'] ?? [for (final point in unit.route) point.toJson()];
        route = _readRoute(path);
        _validateRoute(unit, route);
        if (route.isEmpty) {
          throw const GameActionException(
            'Plan a route before playing Strides.',
          );
        }
      case TacticalCardKind.attack:
        target = _cardTarget(unit, action['target']);
        _validateWeaponTarget(unit, target);
      case TacticalCardKind.skill:
        target = _cardTarget(unit, action['target']);
        final distance = _distance(unit.point, target.point);
        if (distance < 1 || distance > 4) {
          throw const GameActionException('Soul rend reaches 1–4 tiles.');
        }
      case TacticalCardKind.trap:
        final x = action['x'];
        final y = action['y'];
        if (x is! int || y is! int) {
          throw const GameActionException('Choose a tile for the snare.');
        }
        targetPoint = GridPoint(x, y);
        final distance = _distance(unit.point, targetPoint);
        final onPlannedRoute = unit.route.contains(targetPoint);
        if (!_map.inBounds(targetPoint) ||
            !_map.tileAt(targetPoint).passable ||
            (!onPlannedRoute && (distance < 1 || distance > 3))) {
          throw const GameActionException(
            'Place the snare within 3 tiles or on the planned route.',
          );
        }
        if (_unitAt(targetPoint) != null || _trapAt(targetPoint) != null) {
          throw const GameActionException('That tile is occupied.');
        }
      case TacticalCardKind.overwatch:
        break;
    }

    unit.energy -= card.kind.cost;
    if (card.kind == TacticalCardKind.skill) unit.mana--;
    unit.hand.remove(card);
    unit.discardPile.add(card);
    if (unit.retainedCardId == card.id) unit.retainedCardId = null;
    if (card.kind != TacticalCardKind.trap) unit.route = [];

    switch (card.kind) {
      case TacticalCardKind.move:
        final from = unit.point;
        final end = route.last;
        _recordLastAction({
          'type': 'move',
          'unit': unit.id,
          'from': from.toJson(),
          'x': end.x,
          'y': end.y,
          'energy': unit.energy,
          'path': [for (final point in route) point.toJson()],
        });
        for (final point in route) {
          if (!_units.contains(unit)) break;
          unit
            ..x = point.x
            ..y = point.y;
          _triggerTrap(unit);
          if (_units.contains(unit)) _triggerOverwatch(unit);
          if (!_units.contains(unit)) break;
        }
      case TacticalCardKind.attack:
        _resolveCardAttack(
          unit,
          target!,
          damage: 8,
          animation: _attackAnimation(unit),
        );
      case TacticalCardKind.skill:
        _resolveCardAttack(unit, target!, damage: 14, animation: 'special');
      case TacticalCardKind.trap:
        final trapPoint = targetPoint!;
        _traps.add(
          TacticalTrap(
            ownerId: playerId,
            x: trapPoint.x,
            y: trapPoint.y,
            damage: 6,
          ),
        );
        _recordLastAction({
          'type': 'trap',
          'unit': unit.id,
          'animation': 'special',
          'x': trapPoint.x,
          'y': trapPoint.y,
          'energy': unit.energy,
        });
      case TacticalCardKind.overwatch:
        unit.overwatch = true;
        _recordLastAction({
          'type': 'overwatch',
          'unit': unit.id,
          'animation': 'special',
          'energy': unit.energy,
        });
    }
  }

  TacticalUnit _cardTarget(TacticalUnit attacker, Object? targetId) {
    final target = targetId is String ? _unitById(targetId) : null;
    if (target == null || !_isEnemy(attacker, target)) {
      throw const GameActionException('Choose an opposing unit.');
    }
    return target;
  }

  void _validateWeaponTarget(TacticalUnit attacker, TacticalUnit target) {
    final distance = _distance(attacker.point, target.point);
    if (distance < attacker.kind.minimumRange ||
        distance > attacker.kind.range) {
      throw const GameActionException('That enemy is outside weapon range.');
    }
  }

  void _resolveCardAttack(
    TacticalUnit attacker,
    TacticalUnit target, {
    required int damage,
    required String animation,
  }) {
    target.hp = max(0, target.hp - damage);
    final targetHp = target.hp;
    final x = target.x;
    final y = target.y;
    if (target.hp <= 0) _units.remove(target);
    _recordLastAction({
      'type': 'attack',
      'unit': attacker.id,
      'target': target.id,
      'animation': animation,
      'damage': damage,
      'targetHp': targetHp,
      'x': x,
      'y': y,
    });
    _checkOutcome();
  }

  String _attackAnimation(TacticalUnit unit) => switch (unit.kind) {
    TacticalClass.closeCombat => 'melee',
    TacticalClass.ranged => 'ranged',
    TacticalClass.trapper => 'special',
  };
}
