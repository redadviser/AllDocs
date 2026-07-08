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
}
