import 'package:web_socket_channel/web_socket_channel.dart';

/// Browser connection. Browsers handle keep-alive themselves.
WebSocketChannel connectChannel(Uri uri) => WebSocketChannel.connect(uri);
