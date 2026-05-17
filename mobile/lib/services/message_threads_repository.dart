import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/message_thread.dart';
import 'api_exceptions.dart';

class MessageThreadsRepository {
  MessageThreadsRepository({String? baseUrl}) : baseUrl = baseUrl ?? apiBaseUrl();

  final String baseUrl;

  Future<List<MessageThread>> list({required String clientKey}) async {
    final uri = Uri.parse('$baseUrl/me/message-threads').replace(
      queryParameters: {'clientKey': clientKey},
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => MessageThread.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
