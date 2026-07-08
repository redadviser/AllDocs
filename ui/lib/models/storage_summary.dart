class StorageSummary {
  const StorageSummary({required this.usedGb, required this.totalGb});

  final double usedGb;
  final double totalGb;

  double get usedRatio => totalGb == 0 ? 0 : usedGb / totalGb;
  double get availableGb => totalGb - usedGb;
  int get usedPercent => (usedRatio * 100).round();
}
