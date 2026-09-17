import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/widgets/module_error_view.dart';

import 'package:neuro_toolkit/screens/tool_view/cross_module_navigation.dart';
import 'package:neuro_toolkit/screens/tool_view/module_uri_resolver.dart'
    as uri_resolver;
import 'package:neuro_toolkit/screens/tool_view/tool_view_workspace_controller.dart';

bool isWebViewSupported() {
  if (kIsWeb) {
    return false;
  }
  return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}

void recordModuleLoadFailure(
  ToolViewWorkspaceController workspace,
  String moduleId,
  Uri uri,
  String message,
) {
  if (!workspace.mounted) {
    return;
  }
  workspace.rebuild(() {
    workspace.moduleLoadFailures[moduleId] = ModuleLoadFailure(
      uri: uri,
      message: message,
    );
  });
}

Widget buildModuleLoadFailureState(
  BuildContext context,
  WidgetRef ref,
  ToolViewWorkspaceController workspace,
  Module module,
  ModuleLoadFailure failure,
) {
  final isRemoteHosted = uri_resolver.usesRemoteHostedServices(ref);
  return ModuleErrorView(
    module: module,
    failure: failure,
    isRemoteHosted: isRemoteHosted,
    onRetry: () async {
      workspace.rebuild(() {
        workspace.moduleLoadFailures.remove(module.id);
        workspace.controllers.remove(module.id);
      });
      await workspace.activateModule(module.id, requestFocus: false);
    },
    // Every module depends on the same one launcher server — "change
    // server" always means reconnecting the whole app, never a per-module
    // override, so it's offered regardless of local vs. remote.
    onChangeServer: () => showServerConnectionPopup(context, ref),
  );
}

/// Builds the embedded module surface backed by `flutter_inappwebview`.
///
/// We use `flutter_inappwebview` rather than `webview_flutter` because the
/// latter's macOS/WKWebView backend (a) never implements the native file
/// open-panel delegate, so any in-page `<input type="file">` — e.g.
/// JupyterLab's *Upload Files* button — silently does nothing, and (b) has
/// long-standing compositing repaint issues that make hovering the embedded
/// toolbar flicker. `flutter_inappwebview` wires up the WKUIDelegate open
/// panel (and the Android file chooser) and composites cleanly, fixing both
/// at the platform level — no CSS/JS injection workaround required.
///
/// The widget is keyed by module id and lives inside the [IndexedStack], so
/// the underlying native webview is created once and preserved across tab
/// switches and provider rebuilds (no reload on rebuild).
Widget buildModuleWebView(
  BuildContext context,
  WidgetRef ref,
  ToolViewWorkspaceController workspace,
  Module module,
) {
  final initialUri =
      workspace.pendingModuleRequests.remove(module.id) ??
      uri_resolver.moduleUri(ref, module);
  final tunnelSession = uri_resolver.tunnelSession(ref);
  return InAppWebView(
    key: ValueKey<String>(
      'webview-${uri_resolver.launcherBaseUri(ref)?.authority ?? 'disconnected'}-${module.id}',
    ),
    initialUrlRequest: URLRequest(
      url: WebUri.uri(initialUri),
      headers: tunnelSession?.adminToken.isNotEmpty == true
          ? <String, String>{'X-NMTK-Admin-Token': tunnelSession!.adminToken}
          : null,
    ),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true,
      useShouldOverrideUrlLoading: true,
      transparentBackground: false,
      isInspectable: kDebugMode,
      useOnDownloadStart: true,
    ),
    onWebViewCreated: (controller) {
      workspace.controllers[module.id] = controller;
    },
    onLoadStart: (controller, url) {
      if (!workspace.mounted) {
        return;
      }
      workspace.rebuild(() {
        workspace.moduleLoadFailures.remove(module.id);
      });
    },
    onDownloadStartRequest: (controller, downloadRequest) async {
      final uri = downloadRequest.url;
      final urlString = uri.toString();

      if (urlString.startsWith('blob:')) {
        final base64data = await controller.evaluateJavascript(
          source:
              """
            new Promise((resolve, reject) => {
              var xhr = new XMLHttpRequest();
              xhr.open('GET', '$urlString', true);
              xhr.responseType = 'blob';
              xhr.onload = function(e) {
                if (this.status == 200) {
                  var blob = this.response;
                  var reader = new FileReader();
                  reader.readAsDataURL(blob);
                  reader.onloadend = function() {
                    resolve(reader.result);
                  }
                } else {
                  reject('Failed to fetch blob');
                }
              };
              xhr.send();
            });
          """,
        );

        if (base64data != null && base64data is String) {
          final commaIndex = base64data.indexOf(',');
          if (commaIndex != -1) {
            final b64 = base64data.substring(commaIndex + 1);
            final bytes = base64Decode(b64);
            final savePath = await FilePicker.saveFile(
              dialogTitle: 'Save File',
              fileName: downloadRequest.suggestedFilename ?? 'download',
            );
            if (savePath != null) {
              await File(savePath).writeAsBytes(bytes);
            }
          }
        }
      } else if (urlString.startsWith('data:')) {
        final commaIndex = urlString.indexOf(',');
        if (commaIndex != -1) {
          final b64 = urlString.substring(commaIndex + 1);
          final isBase64 = urlString
              .substring(0, commaIndex)
              .contains(';base64');
          final savePath = await FilePicker.saveFile(
            dialogTitle: 'Save File',
            fileName: downloadRequest.suggestedFilename ?? 'download',
          );
          if (savePath != null) {
            if (isBase64) {
              await File(savePath).writeAsBytes(base64Decode(b64));
            } else {
              await File(savePath).writeAsString(Uri.decodeComponent(b64));
            }
          }
        }
      } else {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          debugPrint('Could not launch download URL: $urlString');
        }
      }
    },
    shouldOverrideUrlLoading: (controller, navigationAction) async {
      final requestUrl = navigationAction.request.url;
      if (requestUrl == null) {
        return NavigationActionPolicy.ALLOW;
      }
      final handled = await handleCrossModuleNavigation(
        context,
        ref,
        workspace,
        module,
        Uri.parse(requestUrl.toString()),
      );
      return handled
          ? NavigationActionPolicy.CANCEL
          : NavigationActionPolicy.ALLOW;
    },
    onReceivedError: (controller, request, error) {
      debugPrint('WebView error for ${module.name}: ${error.description}');
      // Only main-frame failures should surface the module error view.
      // Embedded SPAs like JupyterLab routinely fire sub-resource errors
      // (optional extension probes, favicons) that must not be treated as a
      // page load failure.
      if (request.isForMainFrame == false) {
        return;
      }
      recordModuleLoadFailure(
        workspace,
        module.id,
        request.url,
        error.description,
      );
    },
    onReceivedHttpError: (controller, request, errorResponse) {
      // Same main-frame guard as above: a 404 on a JupyterLab sub-resource
      // is not a frontend load failure.
      if (request.isForMainFrame == false) {
        return;
      }
      final statusCode = errorResponse.statusCode;
      final message = statusCode == null
          ? 'Embedded module request failed before the page could load.'
          : 'Embedded module returned HTTP $statusCode instead of a frontend page.';
      recordModuleLoadFailure(workspace, module.id, request.url, message);
    },
  );
}
