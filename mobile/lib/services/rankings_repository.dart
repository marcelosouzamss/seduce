import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/ranking_entry.dart';
import 'api_exceptions.dart';

class RankingsRepository {
  RankingsRepository({String? baseUrl}) : baseUrl = baseUrl ?? apiBaseUrl();

  final String baseUrl;

  Future<List<RankingEntry>> list({bool? isProfessional}) async {
    final base = Uri.parse('$baseUrl/rankings');
    final uri = isProfessional == null
        ? base
        : base.replace(
            queryParameters: {'isProfessional': isProfessional.toString()},
          );
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => RankingEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<RankingEntry> submit({
    required String clientKey,
    required String name,
    required bool isProfessional,
    required int stars,
    required String testimonial,
  }) async {
    final uri = Uri.parse('$baseUrl/rankings');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'clientKey': clientKey,
            'name': name,
            'isProfessional': isProfessional,
            'stars': stars,
            'testimonial': testimonial,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 201) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final entry = map['entry'] as Map<String, dynamic>;
    return RankingEntry.fromJson(Map<String, dynamic>.from(entry));
  }
}
