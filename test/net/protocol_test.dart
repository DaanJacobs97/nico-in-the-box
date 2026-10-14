import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/net/protocol.dart';

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
}
