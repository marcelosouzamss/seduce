import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/chat_message.dart';
import 'api_exceptions.dart';

class ChatRepository {
  ChatRepository({String? baseUrl}) : baseUrl = baseUrl ?? apiBaseUrl();

  final String baseUrl;

  Future<List<ChatMessage>> fetchMessages({
    required int companionId,
    required String clientKey,
    int afterId = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/companions/$companionId/messages').replace(
      queryParameters: <String, String>{
        'clientKey': clientKey,
        if (afterId > 0) 'afterId': afterId.toString(),
      },
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 15));

    if (res.statusCode == 404) {
      throw CompanionNotFoundException();
    }
    if (res.statusCode != 200) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }

    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<ChatMessage>> sendMessage({
    required int companionId,
    required String clientKey,
    required String text,
  }) async {
    final uri = Uri.parse('$baseUrl/companions/$companionId/messages');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({'clientKey': clientKey, 'text': text}),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode == 404) {
      throw CompanionNotFoundException();
    }
    if (res.statusCode != 201) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }

    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = map['messages'] as List<dynamic>;
    return list
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
