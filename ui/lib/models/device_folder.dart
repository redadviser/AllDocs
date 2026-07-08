class DeviceFolder {
  const DeviceFolder({
    required this.id,
    required this.title,
    required this.itemCount,
    this.path,
  });

  final String id;
  final String title;
  final int itemCount;
  final String? path;

  bool get isLinked => path != null && path!.isNotEmpty;
}
