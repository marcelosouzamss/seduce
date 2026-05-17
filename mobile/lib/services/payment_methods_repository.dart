import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/payment_methods.dart';
import 'api_exceptions.dart';

class PaymentMethodsRepository {
  PaymentMethodsRepository({String? baseUrl}) : baseUrl = baseUrl ?? apiBaseUrl();

  final String baseUrl;

  Future<PaymentMethods> get({required String clientKey}) async {
    final uri = Uri.parse('$baseUrl/me/payment-methods').replace(
      queryParameters: {'clientKey': clientKey},
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return PaymentMethods.fromJson(map);
  }

  Future<PaymentMethods> put({
    required String clientKey,
    required PaymentMethods methods,
  }) async {
    final uri = Uri.parse('$baseUrl/me/payment-methods');
    final res = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'clientKey': clientKey,
            'pixKey': methods.pixKey,
            'bitcoinAddress': methods.bitcoinAddress,
            'creditCardNote': methods.creditCardNote,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw CompanionApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return PaymentMethods.fromJson(map);
  }
}
