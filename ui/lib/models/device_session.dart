class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.platform,
    required this.lastSeenAt,
    required this.isCurrentDevice,
  });

  final String id;
  final String platform;
  final DateTime lastSeenAt;
  final bool isCurrentDevice;
}
