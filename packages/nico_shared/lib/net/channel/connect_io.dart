import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native connection. Pings every 5 s so a host that vanishes without
/// closing the socket (crash, Wi-Fi drop) is noticed quickly.
WebSocketChannel connectChannel(Uri uri) =>
    IOWebSocketChannel.connect(uri, pingInterval: const Duration(seconds: 5));
