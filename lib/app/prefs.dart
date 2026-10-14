import 'package:shared_preferences/shared_preferences.dart';

/// Small per-device preferences.
abstract final class Prefs {
  static const _nicknameKey = 'nickname';

  static Future<String> nickname() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_nicknameKey) ?? '';
    } on Object {
      return '';
    }
  }

  static Future<void> saveNickname(String nickname) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nicknameKey, nickname);
    } on Object {
      // Remembering the nickname is a convenience; ignore storage failures.
    }
  }
}
