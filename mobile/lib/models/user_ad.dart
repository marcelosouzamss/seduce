/// Anúncio criado pelo utilizador (mesmo formato na API pública e em /me/ads).
class UserAd {
  UserAd({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAtMs,
    required this.gender,
    required this.age,
    required this.priceBrl,
    required this.hasLocation,
    required this.isProfessional,
    required this.address,
    required this.photoUrls,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String title;
  final String body;
  final int createdAtMs;
  final String gender;
  final int age;
  final double priceBrl;
  final bool hasLocation;
  final bool isProfessional;
  final String address;
  final List<String> photoUrls;
  final double? latitude;
  final double? longitude;

  String get coverPhotoUrl =>
      photoUrls.isNotEmpty ? photoUrls.first : '';

  factory UserAd.fromJson(Map<String, dynamic> j) {
    final created = j['createdAt'] as String?;
    final ms = created != null
        ? DateTime.parse(created).millisecondsSinceEpoch
        : (j['createdAtMs'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    final photos = j['photoUrls'];
    List<String> urls = [];
    if (photos is List) {
      urls = photos.map((e) => '$e').where((s) => s.isNotEmpty).toList();
    }
    final rate = j['priceBrl'] ?? j['hourlyRateBrl'];
    return UserAd(
      id: j['id'].toString(),
      title: j['title'] as String? ?? j['displayName'] as String? ?? '',
      body: j['body'] as String? ?? j['bio'] as String? ?? '',
      createdAtMs: ms,
      gender: j['gender'] as String? ?? 'feminino',
      age: (j['age'] as num?)?.round() ?? 25,
      priceBrl: rate != null ? (rate as num).toDouble() : 350,
      hasLocation: j['hasLocation'] as bool? ?? false,
      isProfessional: j['isProfessional'] as bool? ?? false,
      address: j['address'] as String? ?? j['city'] as String? ?? '',
      photoUrls: urls,
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
    );
  }
}
