import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/user_ad.dart';
import 'api_exceptions.dart';
import 'companion_repository.dart' show TriFilter, triToBool;

class UserAdsRepository {
  UserAdsRepository({String? baseUrl}) : baseUrl = baseUrl ?? apiBaseUrl();

  final String baseUrl;

  Future<List<UserAd>> list({required String clientKey}) async {
    final uri = Uri.parse('$baseUrl/me/ads').replace(
      queryParameters: {'clientKey': clientKey},
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => UserAd.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Mesmos filtros que [CompanionRepository.fetchFiltered] (distância não aplica aos anúncios no servidor).
  Future<List<UserAd>> fetchPublic({
    double maxDistanceKm = 0,
    String? gender,
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

    final uri = Uri.parse('$baseUrl/ads/public').replace(queryParameters: q);
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => UserAd.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<UserAd> fetchPublicById(String id) async {
    final uri = Uri.parse('$baseUrl/ads/public/$id');
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) {
      throw CompanionApiException(404, 'não encontrado');
    }
    if (res.statusCode != 200) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return UserAd.fromJson(map);
  }

  Future<String> uploadPhoto({
    required String clientKey,
    required List<int> bytes,
    required String filename,
  }) async {
    final uri = Uri.parse('$baseUrl/me/ads/photo');
    final request = http.MultipartRequest('POST', uri)
      ..fields['clientKey'] = clientKey
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename.isEmpty ? 'photo.jpg' : filename,
        ),
      );
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 201) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return map['url'] as String;
  }

  Future<UserAd> add({
    required String clientKey,
    required String title,
    required String body,
    required String gender,
    required int age,
    required double priceBrl,
    required bool hasLocation,
    required bool isProfessional,
    required String address,
    required List<String> photoUrls,
    double? latitude,
    double? longitude,
  }) async {
    final uri = Uri.parse('$baseUrl/me/ads');
    final payload = <String, dynamic>{
      'clientKey': clientKey,
      'title': title,
      'body': body,
      'gender': gender,
      'age': age,
      'priceBrl': priceBrl,
      'hasLocation': hasLocation,
      'isProfessional': isProfessional,
      'address': address,
      'photoUrls': photoUrls,
    };
    if (hasLocation && latitude != null && longitude != null) {
      payload['latitude'] = latitude;
      payload['longitude'] = longitude;
    }
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 201) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final ad = map['ad'] as Map<String, dynamic>;
    return UserAd.fromJson(Map<String, dynamic>.from(ad));
  }

  Future<void> remove({required String clientKey, required String id}) async {
    final uri = Uri.parse('$baseUrl/me/ads/$id').replace(
      queryParameters: {'clientKey': clientKey},
    );
    final res = await http.delete(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 204) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
  }
}
