import 'companion.dart';
import 'user_ad.dart';

/// Item na grelha de busca: perfil da base ou anúncio de utilizador.
class DirectoryEntry {
  DirectoryEntry._({required this.isAd, this.companion, this.ad})
      : assert(isAd ? ad != null && companion == null : companion != null && ad == null);

  factory DirectoryEntry.fromCompanion(Companion c) =>
      DirectoryEntry._(isAd: false, companion: c);

  factory DirectoryEntry.fromUserAd(UserAd a) => DirectoryEntry._(isAd: true, ad: a);

  final bool isAd;
  final Companion? companion;
  final UserAd? ad;

  String get key => isAd ? 'a${ad!.id}' : 'c${companion!.id}';

  String get displayName => isAd ? ad!.title : companion!.displayName;

  String get coverPhotoUrl {
    if (isAd) {
      final u = ad!.coverPhotoUrl;
      if (u.isNotEmpty) return u;
      return 'https://picsum.photos/seed/adplaceholder/600/800';
    }
    return companion!.photoUrl;
  }

  int get age => isAd ? ad!.age : companion!.age;

  double get hourlyRateBrl => isAd ? ad!.priceBrl : companion!.hourlyRateBrl;

  /// Texto da linha secundária (cartão).
  String subtitleLine() {
    if (isAd) {
      return '${ad!.age} anos · Anúncio · R\$${ad!.priceBrl.round()}/h';
    }
    final c = companion!;
    return '${c.age} anos · ${c.distanceKm.toStringAsFixed(1)} km · R\$${c.hourlyRateBrl.round()}/h';
  }

  static List<DirectoryEntry> mergeLists(List<Companion> companions, List<UserAd> ads) {
    return [
      ...companions.map(DirectoryEntry.fromCompanion),
      ...ads.map(DirectoryEntry.fromUserAd),
    ];
  }
}
