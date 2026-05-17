import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// URL base da API Node.
///
/// Em builds de release para loja, passe `--dart-define=API_BASE_URL=https://...`
/// (veja `gerar-app-bundle.ps1` na raiz do repositório).
String apiBaseUrl() {
  const fromDefine = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  if (fromDefine.trim().isNotEmpty) {
    return fromDefine.trim();
  }
  if (kIsWeb) {
    return 'http://localhost:3000';
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:3000';
  }
  return 'http://localhost:3000';
}
