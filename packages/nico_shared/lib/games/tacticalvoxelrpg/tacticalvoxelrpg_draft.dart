part of 'tacticalvoxelrpg_game.dart';

const tacticalDraftUnitCount = 3;

extension _TacticalBattleDraft on TacticalVoxelRPGSession {
  String get _gamePhase => isOver
      ? 'over'
      : _drafting
      ? 'selection'
      : 'battle';

  int get _draftSecondsRemaining {
    final deadline = _draftDeadline;
    if (!_drafting || deadline == null) return 0;
    final milliseconds = deadline.difference(DateTime.now()).inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds + 999) ~/ 1000;
  }

  void _initializeDraftSelections() {
    for (final player in _players) {
      _draftSelections[player.id] = [];
    }
  }

  void _applyDraftAction(String playerId, Json action) {
    final deadline = _draftDeadline;
    if (deadline != null && !DateTime.now().isBefore(deadline)) {
      _expireDraft();
      return;
    }
    switch (action['type']) {
      case 'draftSelectUnit':
        _selectDraftUnit(playerId, action);
      case 'draftReady':
        _setDraftReady(playerId, action);
      case 'draftTimeout':
        throw const GameActionException(
          'The selection timer is still running.',
        );
      default:
        throw const GameActionException('Finish company selection first.');
    }
  }

  void _selectDraftUnit(String playerId, Json action) {
    if (_readyPlayers.contains(playerId)) {
      throw const GameActionException('Unready before changing your company.');
    }
    final unitId = action['unit'];
    final selected = action['selected'];
    if (unitId is! String || selected is! bool) {
      throw const GameActionException('Choose a hero card to add or remove.');
    }
    final unit = _unitById(unitId);
    if (unit == null || unit.ownerId != playerId) {
      throw const GameActionException('Choose one of your available heroes.');
    }
    final selection = _draftSelections[playerId]!;
    if (selected) {
      if (selection.contains(unitId)) return;
      if (selection.length >= tacticalDraftUnitCount) {
        throw const GameActionException(
          'Your company already has three heroes.',
        );
      }
      selection.add(unitId);
    } else {
      selection.remove(unitId);
    }
  }

  void _setDraftReady(String playerId, Json action) {
    final ready = action['ready'];
    if (ready is! bool) {
      throw const GameActionException('Ready state must be true or false.');
    }
    if (ready &&
        (_draftSelections[playerId]?.length ?? 0) != tacticalDraftUnitCount) {
      throw const GameActionException(
        'Choose three heroes before readying up.',
      );
    }
    if (ready) {
      _readyPlayers.add(playerId);
    } else {
      _readyPlayers.remove(playerId);
    }
    if (_readyPlayers.length == _players.length) _beginBattle();
  }

  void _expireDraft() {
    final deadline = _draftDeadline;
    if (deadline == null || DateTime.now().isBefore(deadline)) {
      throw const GameActionException('The selection timer is still running.');
    }
    _beginBattle(fillMissing: true);
  }

  void _beginBattle({bool fillMissing = false}) {
    for (final player in _players) {
      final available = _units
          .where((unit) => unit.ownerId == player.id)
          .map((unit) => unit.id)
          .toList();
      final selection = _draftSelections[player.id] ?? available;
      if (fillMissing) {
        for (final unitId in available) {
          if (selection.length >= tacticalDraftUnitCount) break;
          if (!selection.contains(unitId)) selection.add(unitId);
        }
      }
      if (selection.length < tacticalDraftUnitCount) {
        throw const GameActionException('Each player needs three heroes.');
      }
    }
    final chosenIds = _players
        .expand((player) => _draftSelections[player.id] ?? const <String>[])
        .toSet();
    _units.removeWhere(
      (unit) => unit.ownerId != tacticalAiId && !chosenIds.contains(unit.id),
    );
    _drafting = false;
    _draftDeadline = null;
    _selectedUnitId = null;
  }

  void _addTeam(String owner, List<GridPoint> spawns) {
    const classes = [
      TacticalClass.closeCombat,
      TacticalClass.ranged,
      TacticalClass.trapper,
    ];
    const slimeSprites = ['acid', 'dark', 'fire', 'plasma', 'water'];
    const playerNames = ['Aldric', 'Seren', 'Mora'];
    const playerRoles = ['THE OATHKEEPER', 'THE WAYFARER', 'THE HEXWEAVER'];
    const enemyNames = ['Hollow guard', 'Hollow archer', 'Blight hound'];
    const enemyHp = [18, 16, 14];
    for (var i = 0; i < classes.length; i++) {
      final isEnemy = owner == tacticalAiId;
      final sprite = isEnemy
          ? slimeSprites[_random.nextInt(slimeSprites.length)]
          : null;
      final unit = TacticalUnit(
        id: '$owner-${classes[i].name}',
        ownerId: owner,
        kind: classes[i],
        x: spawns[i].x,
        y: spawns[i].y,
        hp: isEnemy ? enemyHp[i] : classes[i].startingHp,
        maxHp: isEnemy ? enemyHp[i] : classes[i].maximumHp,
        mana: isEnemy ? 0 : classes[i].maximumMana,
        maxMana: isEnemy ? 0 : classes[i].maximumMana,
        displayName: isEnemy ? enemyNames[i] : playerNames[i],
        role: isEnemy ? 'THE HOLLOWED' : playerRoles[i],
        sprite: sprite,
      );
      _units.add(unit);
      if (!isEnemy) _initializeCards(unit);
    }
  }
}
