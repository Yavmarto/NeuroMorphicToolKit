part of 'main.dart';

class NeuroToolkitApp extends ConsumerWidget {
  const NeuroToolkitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsProvider);
    final settings = settingsState.value;
    if (settings == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: ZetaProgressCircle(size: ZetaCircleSizes.s)),
        ),
      );
    }
    return NmtkZetaTheme.wrap(
      builder: (context, light, dark, mode) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'NeuroToolkit',
        theme: settings.isHighContrast
            ? AppTheme.highContrastLightTheme
            : light,
        darkTheme: settings.isHighContrast
            ? AppTheme.highContrastDarkTheme
            : dark,
        themeMode: settings.isHighContrast ? settings.themeMode : mode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ServerAccessGate(child: LauncherAppHost()),
        builder: (BuildContext ctx, Widget? child) {
          final commands = ref.watch(commandStateProvider);
          return NmtkShortcutScope(
            globalCommands: commands,
            child: MediaQuery(
              data: MediaQuery.of(ctx).copyWith(
                textScaler: TextScaler.linear(settings.fontSizeFactor),
              ),
              child: child == null
                  ? const SizedBox.shrink()
                  // App-wide top-right notification banners; mounted above the
                  // Navigator so they paint over every route and dialog.
                  : NmtkNotificationCenter(child: child),
            ),
          );
        },
      ),
    );
  }
}
