import 'storage_summary.dart';

class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    required this.planName,
    required this.documentsCount,
    required this.categoriesCount,
    required this.favoritesCount,
    required this.storageSummary,
  });

  final String name;
  final String email;
  final String planName;
  final int documentsCount;
  final int categoriesCount;
  final int favoritesCount;
  final StorageSummary storageSummary;

  UserProfile copyWith({
    String? name,
    String? email,
    String? planName,
    int? documentsCount,
    int? categoriesCount,
    int? favoritesCount,
    StorageSummary? storageSummary,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      planName: planName ?? this.planName,
      documentsCount: documentsCount ?? this.documentsCount,
      categoriesCount: categoriesCount ?? this.categoriesCount,
      favoritesCount: favoritesCount ?? this.favoritesCount,
      storageSummary: storageSummary ?? this.storageSummary,
    );
  }
}
