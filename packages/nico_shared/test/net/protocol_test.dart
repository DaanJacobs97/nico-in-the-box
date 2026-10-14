import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/net/protocol.dart';

void main() {
  test('encode/decode round trip keeps type and body', () {
    final raw = encodeMessage(Msg.hello, {
      'nickname': 'Nico',
      'protocol': kProtocolVersion,
    });
    final msg = decodeMessage(raw);
    expect(msg['type'], Msg.hello);
    expect(msg['nickname'], 'Nico');
    expect(msg['protocol'], kProtocolVersion);
  });

  test('decode rejects non-objects, untyped objects and binary frames', () {
    expect(() => decodeMessage('[1,2]'), throwsFormatException);
    expect(() => decodeMessage('{"a":1}'), throwsFormatException);
    expect(() => decodeMessage('not json'), throwsFormatException);
    expect(() => decodeMessage(<int>[1, 2]), throwsFormatException);
  });

  test('nickname normalization trims and enforces length', () {
    expect(normalizeNickname('  Nico  '), 'Nico');
    expect(normalizeNickname('   '), isNull);
    expect(
      normalizeNickname('a' * kMaxNicknameLength),
      'a' * kMaxNicknameLength,
    );
    expect(normalizeNickname('a' * (kMaxNicknameLength + 1)), isNull);
  });

  test('lobby state survives JSON round trip', () {
    const lobby = LobbyState(
      roomName: 'Party',
      gameId: 'tictactoe',
      players: [
        PlayerInfo(id: 'p1', nickname: 'Host'),
        PlayerInfo(id: 'p2', nickname: 'Guest'),
      ],
      minPlayers: 2,
      maxPlayers: 2,
      hostId: 'p1',
      phase: RoomPhase.playing,
    );
    final decoded = LobbyState.fromJson(
      decodeMessage(encodeMessage(Msg.lobby, lobby.toJson())),
    );
    expect(decoded.roomName, 'Party');
    expect(decoded.players.map((p) => p.nickname), ['Host', 'Guest']);
    expect(decoded.hostId, 'p1');
    expect(decoded.phase, RoomPhase.playing);
    expect(decoded.canStart, isTrue);
    expect(decoded.nicknameOf('p2'), 'Guest');
  });

  group('shared screen', () {
    const settings = DisplaySettings(
      enabled: true,
      target: DisplayTarget.caster,
      hostPlays: false,
    );
    const lobby = LobbyState(
      roomName: 'Party',
      gameId: 'colorclash',
      players: [PlayerInfo(id: 'p2', nickname: 'Guest', isWeb: true)],
      minPlayers: 2,
      maxPlayers: 4,
      hostId: 'p1',
      hostName: 'Nico',
      phase: RoomPhase.lobby,
      display: settings,
      displays: [DisplayInfo(kind: DisplayKind.host, name: 'Nico')],
    );

    test('lobby keeps display settings, screens and the seatless host', () {
      final decoded = LobbyState.fromJson(
        decodeMessage(encodeMessage(Msg.lobby, lobby.toJson())),
      );
      expect(decoded.display, settings);
      expect(decoded.displays.single.kind, DisplayKind.host);
      expect(decoded.sharedScreenActive, isTrue);
      // The host has no seat but is still known by name.
      expect(decoded.nicknameOf('p1'), 'Nico');
      expect(decoded.players.single.isWeb, isTrue);
    });

    test('compact view only while enabled AND a screen is connected', () {
      LobbyState with_(DisplaySettings d, List<DisplayInfo> screens) =>
          LobbyState(
            roomName: 'r',
            gameId: 'g',
            players: const [],
            minPlayers: 2,
            maxPlayers: 2,
            hostId: null,
            phase: RoomPhase.lobby,
            display: d,
            displays: screens,
          );
      const browser = DisplayInfo(kind: DisplayKind.browser, name: 'B');
      expect(with_(DisplaySettings.off, [browser]).sharedScreenActive, isFalse);
      expect(with_(settings, const []).sharedScreenActive, isFalse);
      expect(with_(settings, [browser]).sharedScreenActive, isTrue);
    });

    test('display state round trip', () {
      final state = DisplayState(
        lobby: lobby,
        gameId: 'colorclash',
        table: const {'turn': 'p2'},
        result: const {'summary': 'Guest wins the round!'},
      );
      final decoded = DisplayState.fromJson(
        decodeMessage(encodeMessage(Msg.display, state.toJson())),
      );
      expect(decoded.gameId, 'colorclash');
      expect(decoded.table, {'turn': 'p2'});
      expect(decoded.result!['summary'], 'Guest wins the round!');
      expect(decoded.lobby.roomName, 'Party');
    });
  });
}
