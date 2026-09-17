class StudioNeurochipHandoffContract {
  const StudioNeurochipHandoffContract._({
    required this.studioTargetId,
    required this.neurochipTargetId,
    required this.targetLabel,
    required this.destinationWorkspace,
  });

  final String studioTargetId;
  final String neurochipTargetId;
  final String targetLabel;
  final String destinationWorkspace;

  static const StudioNeurochipHandoffContract fallback = teensy;

  static const StudioNeurochipHandoffContract teensy =
      StudioNeurochipHandoffContract._(
        studioTargetId: 'teensy',
        neurochipTargetId: 'teensy41',
        targetLabel: 'Teensy 4.1',
        destinationWorkspace: 'teensy',
      );

  static const StudioNeurochipHandoffContract pynq =
      StudioNeurochipHandoffContract._(
        studioTargetId: 'pynq',
        neurochipTargetId: 'pynq',
        targetLabel: 'PYNQ',
        destinationWorkspace: 'pynq',
      );

  static const StudioNeurochipHandoffContract akida =
      StudioNeurochipHandoffContract._(
        studioTargetId: 'akida',
        neurochipTargetId: 'akida',
        targetLabel: 'Akida',
        destinationWorkspace: 'akida',
      );

  static const List<StudioNeurochipHandoffContract> values =
      <StudioNeurochipHandoffContract>[teensy, pynq, akida];

  static StudioNeurochipHandoffContract fromStudioTargetId(
    String? studioTargetId,
  ) {
    if (studioTargetId == null || studioTargetId.trim().isEmpty) {
      return fallback;
    }

    for (final target in values) {
      if (target.studioTargetId == studioTargetId) {
        return target;
      }
    }
    return fallback;
  }

  static StudioNeurochipHandoffContract? fromNeurochipTargetId(
    String? neurochipTargetId,
  ) {
    if (neurochipTargetId == null || neurochipTargetId.trim().isEmpty) {
      return null;
    }

    for (final target in values) {
      if (target.neurochipTargetId == neurochipTargetId) {
        return target;
      }
    }
    return null;
  }

  static StudioNeurochipHandoffContract? fromDestinationWorkspace(
    String? destinationWorkspace,
  ) {
    if (destinationWorkspace == null || destinationWorkspace.trim().isEmpty) {
      return null;
    }

    for (final target in values) {
      if (target.destinationWorkspace == destinationWorkspace) {
        return target;
      }
    }
    return null;
  }

  static StudioNeurochipHandoffContract? resolve({
    required String? neurochipTargetId,
    required String? destinationWorkspace,
  }) {
    return fromNeurochipTargetId(neurochipTargetId) ??
        fromDestinationWorkspace(destinationWorkspace);
  }
}
