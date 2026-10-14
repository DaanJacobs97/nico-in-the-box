import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/net/game_server.dart';
import 'package:nico_in_the_box/net/web_files.dart';
import 'package:nico_shared/games/tictactoe/tictactoe_game.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/net/protocol.dart';

final _clientFiles = MemoryWebFiles({
  'index.html': utf8.encode('<html>client</html>'),
  'main.dart.js': utf8.encode('console.log("hi")'),
  'canvaskit/chromium/canvaskit.wasm': [0, 97, 115, 109],
});

void main() {
  late GameServer server;
  late HttpClient http;

  Future<GameServer> startServer({WebFiles? webClient}) async {
    final s = GameServer(
      roomName: 'Web <room>',
      game: ticTacToeDefinition,
      webClient: webClient,
    );
    await s.start(port: 0, address: InternetAddress.loopbackIPv4);
    return s;
  }

  Future<HttpClientResponse> request(
    String path, {
    String method = 'GET',
    bool followRedirects = true,
  }) async {
    final req = await http.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    req.followRedirects = followRedirects;
    return req.close();
  }

  setUp(() async {
    http = HttpClient();
    server = await startServer(webClient: _clientFiles);
  });

  tearDown(() async {
    http.close(force: true);
    await server.close();
  });

  test(
    'landing page links to the browser client and escapes the room',
    () async {
      final res = await request('/');
      expect(res.statusCode, HttpStatus.ok);
      expect(res.headers.contentType?.mimeType, 'text/html');
      final body = await utf8.decodeStream(res);
      expect(body, contains('href="/play/"'));
      expect(body, contains('Web &lt;room&gt;'));
    },
  );

  test('/play redirects to /play/ (the client base href)', () async {
    final res = await request('/play', followRedirects: false);
    expect(res.statusCode, HttpStatus.movedPermanently);
    expect(res.headers.value(HttpHeaders.locationHeader), '/play/');
    await res.drain<void>();
  });

  test('serves client files with the right content types', () async {
    final index = await request('/play/');
    expect(index.statusCode, HttpStatus.ok);
    expect(index.headers.contentType?.mimeType, 'text/html');
    expect(index.headers.value(HttpHeaders.cacheControlHeader), 'no-cache');
    expect(await utf8.decodeStream(index), '<html>client</html>');

    final js = await request('/play/main.dart.js');
    expect(js.headers.contentType?.mimeType, 'text/javascript');
    await js.drain<void>();

    final wasm = await request('/play/canvaskit/chromium/canvaskit.wasm');
    expect(wasm.headers.contentType?.mimeType, 'application/wasm');
    final bytes = await wasm.fold<List<int>>([], (all, b) => all..addAll(b));
    expect(bytes, [0, 97, 115, 109]);
  });

  test('unknown paths, traversal and non-GET requests are refused', () async {
    for (final path in ['/play/nope.js', '/elsewhere', '/play/../secret']) {
      final res = await request(path);
      expect(res.statusCode, HttpStatus.notFound, reason: path);
      await res.drain<void>();
    }
    final post = await request('/', method: 'POST');
    expect(post.statusCode, HttpStatus.methodNotAllowed);
    await post.drain<void>();
  });

  test('gzips responses for clients that accept it', () async {
    final req = await http.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/play/main.dart.js'),
    );
    http.autoUncompress = false;
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
    final res = await req.close();
    expect(res.headers.value(HttpHeaders.contentEncodingHeader), 'gzip');
    await res.drain<void>();
  });

  test('without a bundled client, /play/ explains instead of 404', () async {
    await server.close();
    server = await startServer();
    final res = await request('/play/');
    expect(res.statusCode, HttpStatus.serviceUnavailable);
    expect(await utf8.decodeStream(res), contains('built without'));

    final landing = await utf8.decodeStream(await request('/'));
    expect(landing, isNot(contains('href="/play/"')));
  });

  test('players still join over /ws next to the web routes', () async {
    final host = await GameClient.connect(
      host: '127.0.0.1',
      port: server.port,
      nickname: 'Nico',
      hostToken: server.hostToken,
    );
    expect(host.isHost, isTrue);
    await host.leave();
  });

  test('a hello from a browser marks the player as web', () async {
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}$kWebSocketPath',
    );
    socket.add(
      encodeMessage(Msg.hello, {
        'nickname': 'Browser',
        'protocol': kProtocolVersion,
        'client': 'web',
      }),
    );
    final lobby = await socket
        .map(decodeMessage)
        .firstWhere((m) => m['type'] == Msg.lobby);
    final players = LobbyState.fromJson(lobby).players;
    expect(players.single.nickname, 'Browser');
    expect(players.single.isWeb, isTrue);
    await socket.close();
  });

  group('MemoryWebFiles.fromZip', () {
    Uint8List zip(Map<String, String> files) {
      final archive = Archive();
      files.forEach((name, text) {
        archive.addFile(ArchiveFile.bytes(name, utf8.encode(text)));
      });
      return ZipEncoder().encodeBytes(archive);
    }

    test('unpacks files and serves index.html for the root', () {
      final files = MemoryWebFiles.fromZip(
        zip({'index.html': 'i', 'assets/FontManifest.json': '[]'}),
      );
      expect(files.length, 2);
      expect(utf8.decode(files.lookup('')!.bytes), 'i');
      expect(
        files.lookup('assets/FontManifest.json')!.contentType,
        'application/json',
      );
      expect(files.lookup('missing'), isNull);
    });

    test('accepts Windows-style separators from zip tools', () {
      final files = MemoryWebFiles.fromZip(
        zip({r'canvaskit\canvaskit.js': 'x'}),
      );
      expect(files.lookup('canvaskit/canvaskit.js'), isNotNull);
    });
  });
}
