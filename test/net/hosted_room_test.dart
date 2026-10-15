import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/app/screen_awake.dart';
import 'package:nico_in_the_box/net/hosted_room.dart';
import 'package:nico_shared/games/tictactoe/tictactoe_game.dart';
import 'package:nico_shared/net/game_client.dart';

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
    await closed.future.timeout(const Duration(seconds: 15));
    expect(guest.disconnectReason, DisconnectReason.hostClosed);
    await guest.leave();
  });

  test('the screen stays on while hosting, and only then', () async {
    expect(ScreenAwake.holders, 0);
    final room = await HostedRoom.create(
      roomName: 'Awake test',
      game: ticTacToeDefinition,
      nickname: 'Nico',
    );
    expect(ScreenAwake.holders, 1);
    await room.close();
    expect(ScreenAwake.holders, 0);
    // Closing twice must not release someone else's hold.
    await room.close();
    expect(ScreenAwake.holders, 0);
  });
}
