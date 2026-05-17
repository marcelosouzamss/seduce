import 'package:shared_preferences/shared_preferences.dart';

/// Perfil local do utilizador (conta na app, sem backend dedicado).
enum AccountRole { cliente, profissional }

class UserProfile {
  const UserProfile({
    this.displayName = '',
    this.role = AccountRole.cliente,
    this.age,
    this.photoBase64,
  });

  final String displayName;
  final AccountRole role;
  final int? age;
  final String? photoBase64;
}

class UserProfileStore {
  UserProfileStore._();

  static const _kName = 'user_profile_name';
  static const _kRole = 'user_profile_role';
  static const _kAge = 'user_profile_age';
  static const _kPhoto = 'user_profile_photo_b64';

  static Future<UserProfile> load() async {
    final p = await SharedPreferences.getInstance();
    final roleStr = p.getString(_kRole) ?? 'cliente';
    final ageStr = p.getString(_kAge);
    return UserProfile(
      displayName: p.getString(_kName) ?? '',
      role: roleStr == 'profissional' ? AccountRole.profissional : AccountRole.cliente,
      age: ageStr != null ? int.tryParse(ageStr) : null,
      photoBase64: p.getString(_kPhoto),
    );
  }

  static Future<void> save(UserProfile profile) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kName, profile.displayName);
    await p.setString(
      _kRole,
      profile.role == AccountRole.profissional ? 'profissional' : 'cliente',
    );
    if (profile.age != null) {
      await p.setString(_kAge, profile.age.toString());
    } else {
      await p.remove(_kAge);
    }
    if (profile.photoBase64 != null && profile.photoBase64!.isNotEmpty) {
      await p.setString(_kPhoto, profile.photoBase64!);
    } else {
      await p.remove(_kPhoto);
    }
  }
}
