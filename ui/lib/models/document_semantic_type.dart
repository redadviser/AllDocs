/// Closed taxonomy for on-device document classification (see
/// `DocumentClassifier` in services). Kept small and closed deliberately —
/// this backs a UI filter and (for a few types) the expiry-reminder
/// pipeline, not a general-purpose tagging system.
enum DocumentSemanticType {
  invoice,
  receipt,
  contract,
  identityDocument,
  medical,
  insurance,
  warranty,
  other,
}

DocumentSemanticType? documentSemanticTypeFromName(String? raw) {
  if (raw == null) return null;
  for (final value in DocumentSemanticType.values) {
    if (value.name == raw) return value;
  }
  return null;
}
