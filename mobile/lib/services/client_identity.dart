import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Identificador anônimo por dispositivo para isolar conversas no backend.
class ClientIdentity {
  ClientIdentity._();

  static const _prefKey = 'seduce_chat_client_key';
  static const _uuid = Uuid();

  static Future<String> ensureClientKey() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final key = _uuid.v4();
    await prefs.setString(_prefKey, key);
    return key;
  }
}
