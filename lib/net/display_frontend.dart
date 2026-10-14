import 'web_files.dart';

/// The files a browser loads to show the shared screen at `/screen/`.
///
/// Today that is [HtmlDisplayFrontend], a small hand-written page. A Flutter
/// web version could later implement this interface too (see
/// web_client/README.md): it would read the same `/display` feed, and the
/// host would serve it here instead.
abstract class DisplayFrontend implements WebFiles {
  /// Shown in logs and tests.
  String get name;
}

/// The lightweight HTML/JS shared screen bundled from `assets/display/`.
class HtmlDisplayFrontend implements DisplayFrontend {
  HtmlDisplayFrontend(this._files);

  final WebFiles _files;

  @override
  String get name => 'HTML/JS';

  @override
  WebFile? lookup(String path) => _files.lookup(path);
}
