import 'dart:io';

import 'display_frontend.dart';
import 'web_files.dart';
import 'web_pages.dart';

/// Plain HTTP on the game port: the landing page at `/`, the browser player
/// client at `/play/` and the shared screen page at `/screen/`.
/// [webClient] and [screenPage] are null when this build doesn't bundle them.
Future<void> serveWebRequest(
  HttpRequest request, {
  required String roomName,
  required WebFiles? webClient,
  required DisplayFrontend? screenPage,
}) async {
  final path = request.uri.path;
  final response = request.response;
  if (request.method != 'GET' && request.method != 'HEAD') {
    response.statusCode = HttpStatus.methodNotAllowed;
    await response.close();
    return;
  }
  // Files can change between app versions under the same name.
  response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

  if (path == '/' || path == '/index.html') {
    await _sendHtml(
      response,
      landingPage(
        roomName: roomName,
        hasWebClient: webClient != null,
        hasScreen: screenPage != null,
      ),
    );
  } else if (path == '/play') {
    // The client's base href is /play/, so relative URLs need the slash.
    await response.redirect(
      Uri(path: '/play/'),
      status: HttpStatus.movedPermanently,
    );
  } else if (path == '/screen') {
    await response.redirect(
      Uri(path: '/screen/'),
      status: HttpStatus.movedPermanently,
    );
  } else if (path.startsWith('/screen/')) {
    await _serveFile(
      request,
      screenPage,
      path.substring('/screen/'.length),
      missingPage: screenMissingPage,
    );
  } else if (path.startsWith('/play/')) {
    await _serveFile(
      request,
      webClient,
      path.substring('/play/'.length),
      missingPage: webClientMissingPage,
    );
  } else {
    response.statusCode = HttpStatus.notFound;
    await response.close();
  }
}

Future<void> _serveFile(
  HttpRequest request,
  WebFiles? files,
  String path, {
  required String Function() missingPage,
}) async {
  final response = request.response;
  if (files == null) {
    response.statusCode = HttpStatus.serviceUnavailable;
    await _sendHtml(response, missingPage());
    return;
  }
  final file = files.lookup(path);
  if (file == null) {
    response.statusCode = HttpStatus.notFound;
    await response.close();
    return;
  }
  response.headers.contentType = ContentType.parse(file.contentType);
  if (request.method == 'GET') response.add(file.bytes);
  await response.close();
}

Future<void> _sendHtml(HttpResponse response, String html) async {
  response.headers.contentType = ContentType.html;
  response.write(html);
  await response.close();
}
