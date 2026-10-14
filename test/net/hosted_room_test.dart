import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/games/tictactoe/tictactoe_game.dart';
import 'package:nico_in_the_box/net/game_client.dart';
import 'package:nico_in_the_box/net/hosted_room.dart';

void main() {
  test('closing a hosted room tells guests the host closed it', () async {
    final room = await HostedRoom.create(
      roomName: 'Close test',
      game: ticTacToeDefinition,
      nickname: 'Nico',
    );
    expect(room.client.isHost, isTrue);

    final guest = await GameClient.connect(
      host: '127.0.0.1',
      port: room.port,
      nickname: 'Daan',
    );
    final closed = Completer<void>();
    guest.addListener(() {
      if (guest.disconnectReason != null && !closed.isCompleted) {
        closed.complete();
      }
    });

    await room.close();
    await closed.future.timeout(const Duration(seconds: 5));
    expect(guest.disconnectReason, DisconnectReason.hostClosed);
    await guest.leave();
  });
}
