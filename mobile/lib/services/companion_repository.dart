import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/companion.dart';
import 'api_exceptions.dart';

enum TriFilter { any, yes, no }

bool? triToBool(TriFilter t) =>
    switch (t) {
      TriFilter.any => null,
      TriFilter.yes => true,
      TriFilter.no => false,
    };

class CompanionRepository {
  CompanionRepository({String? baseUrl}) : baseUrl = baseUrl ?? apiBaseUrl();

  final String baseUrl;

  Future<List<Companion>> fetchFiltered({
    required double maxDistanceKm,
    String? gender, // null or 'todos' = all
    required int minAge,
    required int maxAge,
    required TriFilter hasLocationFilter,
    required TriFilter professionalFilter,
    double? minHourlyRateBrl,
    double? maxHourlyRateBrl,
  }) async {
    final hasLoc = triToBool(hasLocationFilter);
    final prof = triToBool(professionalFilter);

    final q = <String, String>{
      'maxDistance': maxDistanceKm.toString(),
      'minAge': minAge.toString(),
      'maxAge': maxAge.toString(),
    };
    if (gender != null && gender != 'todos') {
      q['gender'] = gender;
    }
    if (hasLoc != null) {
      q['hasLocation'] = hasLoc.toString();
    }
    if (prof != null) {
      q['isProfessional'] = prof.toString();
    }
    if (minHourlyRateBrl != null) {
      q['minHourlyRate'] = minHourlyRateBrl.toString();
    }
    if (maxHourlyRateBrl != null) {
      q['maxHourlyRate'] = maxHourlyRateBrl.toString();
    }

    final uri = Uri.parse('$baseUrl/companions').replace(queryParameters: q);
    final res = await http.get(uri).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }

    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => Companion.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Companion> fetchById(int id) async {
    final uri = Uri.parse('$baseUrl/companions/$id');
    final res = await http.get(uri).timeout(const Duration(seconds: 15));

    if (res.statusCode == 404) {
      throw CompanionNotFoundException();
    }
    if (res.statusCode != 200) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }

    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return Companion.fromJson(map);
  }
}
