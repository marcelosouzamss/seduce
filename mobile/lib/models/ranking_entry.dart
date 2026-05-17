class RankingEntry {
  RankingEntry({
    required this.id,
    required this.name,
    required this.isProfessional,
    required this.stars,
    required this.testimonial,
  });

  final String id;
  final String name;
  final bool isProfessional;
  final int stars;
  final String testimonial;

  factory RankingEntry.fromJson(Map<String, dynamic> j) {
    return RankingEntry(
      id: j['id'].toString(),
      name: j['name'] as String,
      isProfessional: j['isProfessional'] as bool,
      stars: (j['stars'] as num).round().clamp(1, 5),
      testimonial: j['testimonial'] as String,
    );
  }
}
