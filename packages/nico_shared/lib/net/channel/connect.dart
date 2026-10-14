// Picks the WebSocket implementation for the platform: dart:io on native
// (with keep-alive pings), the browser's WebSocket on the web.
export 'connect_web.dart' if (dart.library.io) 'connect_io.dart';
