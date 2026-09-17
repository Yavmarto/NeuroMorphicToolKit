import 'package:neuro_toolkit/features/neurocnl/services/workspace_cache_storage_base.dart';
import 'package:neuro_toolkit/features/neurocnl/services/workspace_cache_storage_stub.dart'
    if (dart.library.io) 'workspace_cache_storage_io.dart'
    as implementation;

export 'package:neuro_toolkit/features/neurocnl/services/workspace_cache_storage_base.dart';

WorkspaceCacheStorage? createWorkspaceCacheStorage() =>
    implementation.createWorkspaceCacheStorage();
