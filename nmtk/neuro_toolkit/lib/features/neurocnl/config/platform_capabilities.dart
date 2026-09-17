import 'package:flutter/foundation.dart';

/// True only where `webview_flutter` has a platform implementation. Its
/// pubspec declares platforms for android, ios and macos only, so on web,
/// Linux and Windows `WebViewPlatform.instance` is null and constructing a
/// `WebViewController` throws.
bool get supportsEmbeddedWebView =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);
