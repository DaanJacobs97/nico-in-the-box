/// Small HTML pages the host serves itself (no assets needed).
library;

String _page(String title, String body) =>
    '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>
  :root { color-scheme: light dark; --accent: #673ab7; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center;
         font-family: system-ui, sans-serif; background: Canvas; color: CanvasText; }
  main { max-width: 420px; padding: 24px; text-align: center; }
  h1 { font-size: 2rem; margin: 0 0 8px; }
  p { line-height: 1.5; opacity: .8; }
  a.button { display: block; margin: 24px 0 8px; padding: 16px; border-radius: 16px;
             background: var(--accent); color: #fff; font-size: 1.2rem;
             font-weight: 600; text-decoration: none; }
</style>
</head>
<body><main>$body</main></body>
</html>
''';

/// Landing page at `/`, so typing just the host's address leads somewhere.
String landingPage({required String roomName, required bool hasWebClient}) {
  final room = _escape(roomName);
  return _page(
    'Nico in the Box',
    hasWebClient
        ? '''
<h1>Nico in the Box</h1>
<p>Room: <strong>$room</strong></p>
<a class="button" href="/play/">Join as player</a>
<p>Have the app? Open it and use <em>Join a game</em> instead.</p>
'''
        : '''
<h1>Nico in the Box</h1>
<p>Room: <strong>$room</strong></p>
<p>Joining from a browser isn't included in this build of the host app.
Open the <em>Nico in the Box</em> app and use <em>Join a game</em>.</p>
''',
  );
}

/// Shown at `/play/` when the host app was built without the web client.
String webClientMissingPage() => _page('Not available', '''
<h1>Not available</h1>
<p>This host app was built without the browser client.
Open the <em>Nico in the Box</em> app to join, or ask the host to rebuild with
<code>tool/build_web_client</code>.</p>
''');

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
