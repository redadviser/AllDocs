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
    this.avatarUrl,
  });

  final String name;
  final String email;
  final String planName;
  final int documentsCount;
  final int categoriesCount;
  final int favoritesCount;
  final StorageSummary storageSummary;
  // A Google account photo URL, or a local file path for a manually picked
  // photo (no blob-storage backend yet to upload one to). Null shows initials.
  final String? avatarUrl;

  UserProfile copyWith({
    String? name,
    String? email,
    String? planName,
    int? documentsCount,
    int? categoriesCount,
    int? favoritesCount,
    StorageSummary? storageSummary,
    String? avatarUrl,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      planName: planName ?? this.planName,
      documentsCount: documentsCount ?? this.documentsCount,
      categoriesCount: categoriesCount ?? this.categoriesCount,
      favoritesCount: favoritesCount ?? this.favoritesCount,
      storageSummary: storageSummary ?? this.storageSummary,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
