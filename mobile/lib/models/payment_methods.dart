class PaymentMethods {
  PaymentMethods({
    this.pixKey,
    this.bitcoinAddress,
    this.creditCardNote,
  });

  final String? pixKey;
  final String? bitcoinAddress;
  final String? creditCardNote;

  Map<String, dynamic> toJson() => {
        'pixKey': pixKey,
        'bitcoinAddress': bitcoinAddress,
        'creditCardNote': creditCardNote,
      };

  factory PaymentMethods.fromJson(Map<String, dynamic> j) {
    return PaymentMethods(
      pixKey: j['pixKey'] as String?,
      bitcoinAddress: j['bitcoinAddress'] as String?,
      creditCardNote: j['creditCardNote'] as String?,
    );
  }

  factory PaymentMethods.empty() => PaymentMethods();
}
