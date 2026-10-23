import 'package:flutter/services.dart';

/// Asset keys of the art games draw (`Image.asset(..., package:
/// 'nico_shared')`) start with this.
const gameArtPrefix = 'packages/nico_shared/';

/// Game art the host serves to browsers. The browser client's zip leaves
/// `nico_shared`'s assets out (see `tool/build_web_client`), because the host
/// app bundles the same files anyway; the `/screen/` page uses them too.
abstract class GameArt {
  /// The bytes of the asset [key] (such as
  /// `packages/nico_shared/assets/tacticalvoxelrpg/characters/mora.png`), or
  /// null when there is no such asset.
  Future<List<int>?> load(String key);
}

/// [GameArt] from the app's own asset bundle, loaded on request.
class BundleGameArt implements GameArt {
  const BundleGameArt([this._bundle]);

  final AssetBundle? _bundle;

  @override
  Future<List<int>?> load(String key) async {
    try {
      final data = await (_bundle ?? rootBundle).load(key);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      return null;
    }
  }
}

/// The asset key for a requested [path] under [gameArtPrefix], or null when
/// it isn't one (outside the prefix, or trying to climb out with `..`).
String? gameArtKey(String path) {
  final String key;
  try {
    key = Uri.decodeFull(path);
  } on ArgumentError {
    return null;
  }
  if (!key.startsWith(gameArtPrefix) ||
      key.contains('\\') ||
      key
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    return null;
  }
  return key;
}
