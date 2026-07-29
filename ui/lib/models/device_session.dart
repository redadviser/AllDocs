class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.platform,
    required this.name,
    required this.lastSeenAt,
    required this.isCurrentDevice,
  });

  final String id;
  final String platform;
  // Null for devices registered before device names were tracked.
  final String? name;
  final DateTime lastSeenAt;
  final bool isCurrentDevice;
}
