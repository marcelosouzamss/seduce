class Companion {
  Companion({
    required this.id,
    required this.displayName,
    required this.photoUrl,
    required this.gender,
    required this.age,
    required this.distanceKm,
    required this.hasLocation,
    required this.isProfessional,
    required this.bio,
    required this.city,
    required this.hourlyRateBrl,
    this.latitude,
    this.longitude,
  });

  final int id;
  final String displayName;
  final String photoUrl;
  final String gender;
  final int age;
  final double distanceKm;
  final bool hasLocation;
  final bool isProfessional;
  final String bio;
  final String city;
  final double hourlyRateBrl;
  final double? latitude;
  final double? longitude;

  factory Companion.fromJson(Map<String, dynamic> j) {
    final rate = j['hourlyRateBrl'] ?? j['hourly_rate_brl'];
    return Companion(
      id: j['id'] as int,
      displayName: j['displayName'] as String,
      photoUrl: j['photoUrl'] as String,
      gender: j['gender'] as String,
      age: j['age'] as int,
      distanceKm: (j['distanceKm'] as num).toDouble(),
      hasLocation: j['hasLocation'] as bool,
      isProfessional: j['isProfessional'] as bool,
      bio: j['bio'] as String,
      city: j['city'] as String,
      hourlyRateBrl: rate != null ? (rate as num).toDouble() : 350,
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
    );
  }
}
