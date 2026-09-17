// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

Future<bool> openExternalUrlImpl(String url) async {
  if (url.startsWith('nmtk://')) {
    html.window.location.href = url;
    return true;
  }
  html.window.open(url, '_blank');
  return true;
}
