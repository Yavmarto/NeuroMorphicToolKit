class SavedHardwareTargetEntry {
  const SavedHardwareTargetEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    this.targetType = 'akida',
    this.isDefault = false,
    this.targetData,
  });

  final String id;
  final String title;
  final String subtitle;
  final String targetType;
  final bool isDefault;
  final Object? targetData;
}
