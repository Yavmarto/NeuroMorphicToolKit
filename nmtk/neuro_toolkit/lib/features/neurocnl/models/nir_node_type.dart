import 'package:flutter/material.dart';

class NirPortDef {
  const NirPortDef({
    required this.id,
    required this.direction,
    required this.label,
  });

  final String id;
  final String direction;
  final String label;
}

class NirParameterDef {
  const NirParameterDef({
    required this.name,
    required this.label,
    required this.type,
    this.description = '',
    this.defaultValue,
    this.min,
    this.max,
    this.unit,
    this.enumValues,
  });

  final String name;
  final String label;
  final String type;
  final String description;
  final Object? defaultValue;
  final double? min;
  final double? max;
  final String? unit;
  final List<String>? enumValues;
}

class NirNodeType {
  const NirNodeType({
    required this.id,
    required this.displayName,
    required this.category,
    required this.icon,
    required this.ports,
    required this.parameters,
    this.legacyComponentId,
    this.baseNirType,
    this.isCustom = false,
  });

  final String id;
  final String displayName;
  final String category;
  final IconData icon;
  final List<NirPortDef> ports;
  final List<NirParameterDef> parameters;
  final String? legacyComponentId;
  final String? baseNirType;
  final bool isCustom;

  Map<String, dynamic> get defaultParameters => <String, dynamic>{
    for (final parameter in parameters)
      if (parameter.defaultValue != null)
        parameter.name: parameter.defaultValue,
  };
}
