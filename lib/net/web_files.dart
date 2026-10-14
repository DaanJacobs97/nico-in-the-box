import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A static file the host serves over HTTP.
class WebFile {
  const WebFile(this.bytes, this.contentType);

  final List<int> bytes;
  final String contentType;
}

/// Static files served under one URL prefix (e.g. the browser client at
/// `/play/`). Lookups use paths relative to that prefix.
abstract class WebFiles {
  /// The file at [path] (no leading slash; empty means `index.html`), or
  /// null if there is none.
  WebFile? lookup(String path);
}

const _contentTypes = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'mjs': 'text/javascript; charset=utf-8',
  'json': 'application/json',
  'wasm': 'application/wasm',
  'css': 'text/css; charset=utf-8',
  'png': 'image/png',
  'ico': 'image/x-icon',
  'otf': 'font/otf',
  'ttf': 'font/ttf',
  'frag': 'application/octet-stream',
  'bin': 'application/octet-stream',
};

String contentTypeFor(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();
  return _contentTypes[ext] ?? 'application/octet-stream';
}

/// Files held in memory, keyed by relative path.
class MemoryWebFiles implements WebFiles {
  MemoryWebFiles(Map<String, List<int>> files)
    : _files = {
        for (final entry in files.entries)
          _normalize(entry.key): WebFile(
            entry.value,
            contentTypeFor(entry.key),
          ),
      };

  /// Unpacks a zip archive, e.g. the bundled browser client.
  factory MemoryWebFiles.fromZip(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    return MemoryWebFiles({
      for (final file in archive.files)
        if (file.isFile) file.name: file.content,
    });
  }

  final Map<String, WebFile> _files;

  int get length => _files.length;

  static String _normalize(String path) =>
      path.replaceAll(r'\', '/').replaceFirst(RegExp('^/+'), '');

  @override
  WebFile? lookup(String path) {
    final key = _normalize(path);
    if (key.split('/').contains('..')) return null;
    return _files[key.isEmpty || key.endsWith('/') ? '${key}index.html' : key];
  }
}
