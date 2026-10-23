import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/net/game_art.dart';
import 'package:nico_in_the_box/net/game_server.dart';
import 'package:nico_in_the_box/net/web_files.dart';
import 'package:nico_shared/games/tictactoe/tictactoe_game.dart';

const _portrait = 'packages/nico_shared/assets/game/hero.png';

/// Game art from memory, recording what was asked for.
class _FakeArt implements GameArt {
  final requested = <String>[];

  @override
  Future<List<int>?> load(String key) async {
    requested.add(key);
    return key == _portrait ? [137, 80, 78, 71] : null;
  }
}

void main() {
  group('serving game art', () {
    late GameServer server;
    late HttpClient http;
    late _FakeArt art;

    Future<void> start({WebFiles? webClient}) async {
      server = GameServer(
        roomName: 'Art room',
        game: ticTacToeDefinition,
        webClient: webClient,
        gameArt: art,
      );
      await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    }

    Future<HttpClientResponse> get(String path) async =>
        (await http.getUrl(Uri.parse('http://127.0.0.1:${server.port}$path')))
            .close();

    setUp(() {
      http = HttpClient();
      art = _FakeArt();
    });

    tearDown(() async {
      http.close(force: true);
      await server.close();
    });

    test('the browser client finds art the zip leaves out', () async {
      await start(
        webClient: MemoryWebFiles({'index.html': utf8.encode('<html/>')}),
      );
      final res = await get('/play/assets/$_portrait');
      expect(res.statusCode, HttpStatus.ok);
      expect(res.headers.contentType?.mimeType, 'image/png');
      expect(await res.fold<List<int>>([], (a, b) => a..addAll(b)), [
        137,
        80,
        78,
        71,
      ]);
      expect(art.requested, [_portrait]);
    });

    test('a file the zip does have still comes from the zip', () async {
      await start(
        webClient: MemoryWebFiles({
          'index.html': utf8.encode('<html/>'),
          'assets/$_portrait': [1, 2, 3],
        }),
      );
      final res = await get('/play/assets/$_portrait');
      expect(await res.fold<List<int>>([], (a, b) => a..addAll(b)), [1, 2, 3]);
      expect(art.requested, isEmpty);
    });

    test('/art/ is the short form for the screen page', () async {
      await start();
      final res = await get('/art/game/hero.png');
      expect(res.statusCode, HttpStatus.ok);
      expect(res.headers.contentType?.mimeType, 'image/png');
      await res.drain<void>();
      expect(art.requested, [_portrait]);
    });

    test('missing art is a 404', () async {
      await start();
      for (final path in [
        '/art/game/nobody.png',
        '/play/assets/packages/nico_shared/assets/game/nobody.png',
      ]) {
        final res = await get(path);
        expect(res.statusCode, HttpStatus.notFound, reason: path);
        await res.drain<void>();
      }
    });

    test('nothing outside nico_shared can be fetched', () async {
      await start();
      for (final path in [
        '/art/../../generated/web_client.zip',
        '/art/%2E%2E/%2E%2E/generated/web_client.zip',
        '/art//game/hero.png',
      ]) {
        final res = await get(path);
        expect(res.statusCode, HttpStatus.notFound, reason: path);
        await res.drain<void>();
      }
      expect(art.requested, isEmpty);
    });
  });

  test('gameArtKey accepts nico_shared asset keys only', () {
    expect(gameArtKey(_portrait), _portrait);
    expect(
      gameArtKey('packages/nico_shared/assets/a%20b.png'),
      'packages/nico_shared/assets/a b.png',
    );
    for (final bad in [
      'packages/other/assets/x.png',
      'assets/display/index.html',
      'packages/nico_shared/../../x',
      'packages/nico_shared/assets/./x.png',
      'packages/nico_shared/assets//x.png',
      r'packages/nico_shared/assets\x.png',
      'packages/nico_shared/assets/%E0%A4%A.png',
    ]) {
      expect(gameArtKey(bad), isNull, reason: bad);
    }
  });

  group('the real asset bundle', () {
    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    test('serves the art games ship with', () async {
      const key =
          'packages/nico_shared/assets/tacticalvoxelrpg/characters/aldric.png';
      final bytes = await const BundleGameArt().load(key);
      expect(bytes, isNotNull);
      expect(bytes!.take(4), [137, 80, 78, 71], reason: 'a PNG');
      expect(
        await const BundleGameArt().load('packages/nico_shared/nope.png'),
        isNull,
      );
    });

    test('every portrait the browser screen asks for exists', () {
      final js = File('assets/display/games/tacticalvoxelrpg.js')
          .readAsStringSync();
      expect(js, contains('/art/tacticalvoxelrpg/characters/'));
      final names = RegExp(r"'([a-z_]+)'")
          .allMatches(js.split('NicoDisplay.register').first)
          .map((m) => m[1]!);
      expect(names, hasLength(6));
      for (final name in names) {
        expect(
          File(
            'packages/nico_shared/assets/tacticalvoxelrpg/characters/$name.png',
          ).existsSync(),
          isTrue,
          reason: name,
        );
      }
    });
  });

  test('the browser screen has no copies of game art', () {
    // Whole contents as the key: a few MB, read once.
    String hash(File f) => base64Encode(f.readAsBytesSync());
    final art = {
      for (final f in Directory(
        'packages/nico_shared/assets',
      ).listSync(recursive: true).whereType<File>())
        hash(f): f.path,
    };
    final copies = [
      for (final f in Directory(
        'assets/display',
      ).listSync(recursive: true).whereType<File>())
        if (art.containsKey(hash(f))) '${f.path} = ${art[hash(f)]}',
    ];
    expect(
      copies,
      isEmpty,
      reason:
          'Link to the art at /art/<game>/... instead (see ADDING_A_GAME.md)',
    );
  });
}
