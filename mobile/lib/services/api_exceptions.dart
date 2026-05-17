class CompanionApiException implements Exception {
  CompanionApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class CompanionNotFoundException implements Exception {}
