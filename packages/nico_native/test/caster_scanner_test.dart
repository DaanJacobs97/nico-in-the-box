import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_native/caster_scanner.dart';
import 'package:nico_native/discovery.dart';
import 'package:nico_shared/net/protocol.dart';

List<int> _packet({bool busy = false}) => utf8.encode(
  jsonEncode(
    CasterAnnouncement(
      id: 'c1',
      name: 'Living room TV',
      port: kCasterPort,
      busy: busy,
    ).toJson(),
  ),
);

void main() {
  test('parses Caster announcements and ignores rooms', () {
    final from = InternetAddress('192.168.0.160');
    final caster = parseCasterAnnouncement(_packet(busy: true), from)!;
    expect(caster.name, 'Living room TV');
    expect(caster.address, from);
    expect(caster.port, kCasterPort);
    expect(caster.busy, isTrue);

    final room = utf8.encode(jsonEncode({'app': kDiscoveryAppId, 'v': 2}));
    expect(parseCasterAnnouncement(room, from), isNull);
    expect(parseCasterAnnouncement([0xff], from), isNull);
  });

  test('scanner hears a Caster and forgets it when it goes quiet', () async {
    const port = 47912;
    final scanner = CasterScanner(
      port: port,
      staleAfter: const Duration(milliseconds: 800),
    );
    await scanner.start();
    expect(scanner.error, isNull);

    final announcer = RoomBroadcaster(
      announcement: _packet,
      port: port,
      interval: const Duration(milliseconds: 100),
      targets: [InternetAddress.loopbackIPv4],
    );
    await announcer.start();

    Future<void> until(bool Function() condition) {
      if (condition()) return Future.value();
      final done = Completer<void>();
      void check() {
        if (!done.isCompleted && condition()) done.complete();
      }

      scanner.addListener(check);
      return done.future
          .timeout(const Duration(seconds: 5))
          .whenComplete(() => scanner.removeListener(check));
    }

    await until(() => scanner.casters.isNotEmpty);
    expect(scanner.casters.single.name, 'Living room TV');

    announcer.stop();
    await until(() => scanner.casters.isEmpty);
    scanner.dispose();
  });
}
