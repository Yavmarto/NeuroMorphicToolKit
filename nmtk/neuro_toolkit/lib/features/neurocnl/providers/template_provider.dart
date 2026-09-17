import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/template.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/server_config_provider.dart';

part 'template_provider.g.dart';

@riverpod
class TemplateController extends _$TemplateController {
  static const _storageKey = 'cached_templates';

  @override
  AsyncValue<List<CnlTemplate>> build() {
    // Re-fetch when the backend URL changes
    ref.listen<String?>(serverConfigProvider.select((s) => s.serverUrl), (
      prev,
      next,
    ) {
      if (next != null && next != prev) {
        fetch();
      }
    });

    final String? cached = ServerConfigService.getString(_storageKey);
    if (cached != null) {
      try {
        final List<dynamic> list = jsonDecode(cached) as List<dynamic>;
        final List<CnlTemplate> templates = list
            .map((t) => CnlTemplate.fromJson(t as Map<String, dynamic>))
            .toList();

        Future.microtask(() {
          if (ref.mounted) fetch();
        });

        return AsyncValue.data(templates);
      } catch (e) {
        debugPrint('Failed to deserialize cached templates: $e');
      }
    }

    Future.microtask(() {
      if (ref.mounted) fetch();
    });

    return const AsyncValue.loading();
  }

  Future<void> fetch() async {
    final api = ref.read(apiClientProvider);
    try {
      final templates = await api.getTemplates();
      state = AsyncValue.data(templates);
      unawaited(
        ServerConfigService.setString(
          _storageKey,
          jsonEncode(templates.map((t) => t.toJson()).toList()),
        ),
      );
    } catch (e, st) {
      if (!state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

/// Backward-compat alias.
final templateProvider = templateControllerProvider;
