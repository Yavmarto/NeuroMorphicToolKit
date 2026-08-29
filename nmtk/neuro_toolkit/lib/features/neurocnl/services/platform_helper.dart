/// Platform abstraction for file download and clipboard operations.
library;

export 'package:neuro_toolkit/features/neurocnl/services/platform_download_result.dart';

///
/// Uses conditional imports to select the correct implementation:
/// - Web: dart:html (Blob + AnchorElement)
/// - Native (macOS/Windows/Linux/iOS/Android): clipboard + browser-capability helpers.
export 'package:neuro_toolkit/features/neurocnl/services/platform_helper_stub.dart'
    if (dart.library.html) 'platform_helper_web.dart';
