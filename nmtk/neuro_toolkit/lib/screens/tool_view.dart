import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/src/features/app/presentation/launcher_navigation_notifier.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';
import 'package:neuro_toolkit/widgets/connection_error_actions.dart';
import 'package:neuro_toolkit/widgets/module_icon.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/screens/tool_view/cross_module_navigation.dart';
import 'package:neuro_toolkit/screens/tool_view/launcher_profile_button.dart';
import 'package:neuro_toolkit/screens/tool_view/module_surface_builder.dart';
import 'package:neuro_toolkit/screens/tool_view/server_connection_control.dart';
import 'package:neuro_toolkit/screens/tool_view/tool_view_workspace_controller.dart';
import 'package:neuro_toolkit/screens/tool_view/tool_view_workspace_host.dart';

class ToolViewScreen extends ConsumerStatefulWidget {
  const ToolViewScreen({super.key});

  @override
  ConsumerState<ToolViewScreen> createState() => _ToolViewScreenState();
}

// Module IDs that are desktop-only and must not appear in the mobile bottom nav.
const _kMobileHiddenModuleIds = {'Neurobench'};

class _ToolViewScreenState extends ConsumerState<ToolViewScreen>
    implements ToolViewWorkspaceHost {
  late final ToolViewWorkspaceController _workspace =
      ToolViewWorkspaceController(this);

  @override
  void rebuild(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    ref.listenManual<LauncherNavigationRequest?>(
      launcherNavigationProvider,
      _workspace.handleLauncherNavigation,
    );
    ref.listenManual<AsyncValue<ModuleState>>(
      moduleProvider,
      _workspace.handleModuleStateChanged,
      fireImmediately: true,
    );
    ref.listenManual<AsyncValue<WorkspaceState>>(
      workspaceProvider,
      _workspace.handleWorkspaceStateChanged,
      fireImmediately: true,
    );
    ref.listenManual<ControlApiService?>(
      selectedControlApiServiceProvider,
      _workspace.handleControlApiChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _workspace.initializeWorkspace();
    });
  }

  /// A compact, host-owned server control for the embedded NeuroCNL toolbar.
  /// Keeping its state and callback here means the Studio package never owns
  /// server selection or creates a parallel connection workflow.
  Widget _buildInlineServerConnectionControl(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineServerConnectionControl(
          onPressed: () => showServerConnectionPopup(context, ref),
        ),
        const SizedBox(width: 8),
        const LauncherProfileButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final moduleStateAsync = ref.watch(moduleProvider);
    final moduleState = moduleStateAsync.value;
    final workspaceStateAsync = ref.watch(workspaceProvider);
    final workspaceState = workspaceStateAsync.value;
    final tokens = NmtkShellTokens.of(context);
    final currentServerKey =
        ref.watch(selectedControlApiServiceProvider)?.baseUri.toString() ??
        'disconnected';

    final eligibleModules = moduleState == null
        ? const <Module>[]
        : moduleState.modules
              .where(_workspace.shouldOpenModule)
              .toList(growable: false);

    if (moduleState == null || workspaceState == null) {
      final loadError = moduleStateAsync.error ?? workspaceStateAsync.error;
      if (loadError != null) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: NmtkEmptyState(
                  title: 'Could Not Load Workspace',
                  message: nmtkUserFacingError(loadError),
                  icon: ZetaIcons.cloud_off,
                  tone: NmtkTone.danger,
                  action: ConnectionErrorActions(
                    onRetry: () {
                      ref.invalidate(moduleProvider);
                      ref.invalidate(workspaceProvider);
                    },
                    onChangeServer: () =>
                        showServerConnectionPopup(context, ref),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return const Scaffold(
        body: Center(child: ZetaProgressCircle(size: ZetaCircleSizes.s)),
      );
    }

    final sessions = workspaceState.sessions;

    // Build the horizontal workspace destinations from the eligible module
    // manifest, not only the currently open workspace sessions.
    final navItems = eligibleModules
        .map(
          (Module module) => NmtkSidebarItem(
            id: module.id,
            label: module.name,
            icon: ModuleIcon.forModule(module),
            selectedIcon: ModuleIcon.forModule(module, selected: true),
          ),
        )
        .toList(growable: false);

    final isMobile = MediaQuery.sizeOf(context).width < 840;

    if (eligibleModules.isEmpty) {
      final emptyState = NmtkEmptyState(
        title: 'NeuroStudio Not Available',
        message:
            'No module surface could be opened for this server. This usually '
            'means the backend is still starting or the server is out of '
            'reach — reconnect or set up your server to continue.',
        icon: ZetaIcons.cloud_off,
        tone: NmtkTone.warning,
        action: ConnectionErrorActions(
          onRetry: () {
            ref.invalidate(moduleProvider);
            ref.invalidate(workspaceProvider);
          },
          onChangeServer: () => showServerConnectionPopup(context, ref),
        ),
      );
      if (isMobile) {
        return NmtkMobileScaffold(
          mode: NmtkShellMode.command,
          navItems: const [],
          selectedIndex: 0,
          pageTitle: 'NeuroToolkit',
          child: emptyState,
        );
      }
      return Scaffold(
        backgroundColor: tokens.shellBackground,
        body: SafeArea(
          top: false,
          bottom: false,
          child: emptyState,
        ),
      );
    }

    final eligibleModuleIds = eligibleModules
        .map((Module module) => module.id)
        .toSet();
    final focusedModuleId = workspaceState.focusedModuleId;

    final desiredModuleId = () {
      if (focusedModuleId != null &&
          eligibleModuleIds.contains(focusedModuleId) &&
          focusedModuleId != _workspace.activeModuleId) {
        return focusedModuleId;
      }
      if (!eligibleModuleIds.contains(_workspace.activeModuleId)) {
        return eligibleModules.first.id;
      }
      return _workspace.activeModuleId;
    }();
    final selectedIndex = navItems.indexWhere(
      (NmtkSidebarItem item) => item.id == desiredModuleId,
    );
    final clampedIndex = selectedIndex < 0 ? 0 : selectedIndex;

    final sessionsByModuleId = <String, WorkspaceSession>{
      for (final session in sessions) session.moduleId: session,
    };

    if (isMobile) {
      // On mobile, filter out desktop-only modules (e.g. Neurobench) from the
      // bottom nav and the content stack. Both lists must stay in sync so that
      // selectedIndex correctly maps a nav tap to its content pane.
      final mobileModules = eligibleModules
          .where((m) => !_kMobileHiddenModuleIds.contains(m.id))
          .toList(growable: false);
      final mobileNavItems = mobileModules
          .map(
            (Module module) => NmtkSidebarItem(
              id: module.id,
              label: module.name,
              icon: ModuleIcon.forModule(module),
              selectedIcon: ModuleIcon.forModule(module, selected: true),
            ),
          )
          .toList(growable: false);
      // If the currently active module is hidden on mobile, fall back to the
      // first visible module so the user always sees a valid pane.
      final mobileActiveId = _kMobileHiddenModuleIds.contains(desiredModuleId)
          ? (mobileModules.isNotEmpty
                ? mobileModules.first.id
                : desiredModuleId)
          : desiredModuleId;
      final mobileSelectedIndex = mobileNavItems.indexWhere(
        (item) => item.id == mobileActiveId,
      );
      final mobileClampedIndex = mobileSelectedIndex < 0
          ? 0
          : mobileSelectedIndex;
      final mobileActiveModule = mobileModules.isNotEmpty
          ? mobileModules[mobileClampedIndex]
          : null;
      final mobileActiveSession = mobileActiveModule != null
          ? sessionsByModuleId[mobileActiveModule.id]
          : null;
      final mobileActiveModuleIsReady =
          mobileActiveModule != null &&
          (mobileActiveModule.status == ModuleStatus.running ||
              mobileActiveModule.status == ModuleStatus.degraded);
      final showMobileInlineServerControl =
          mobileActiveModule?.id == 'neurocnl' &&
          mobileActiveModuleIsReady &&
          mobileActiveSession?.surfaceMode == 'native';

      return NmtkMobileScaffold(
        mode: NmtkShellMode.command,
        navItems: mobileNavItems,
        selectedIndex: mobileClampedIndex,
        onNavItemSelected: (i) {
          if (i < mobileNavItems.length) {
            setState(() => _workspace.activeModuleId = mobileNavItems[i].id);
          }
        },
        showBottomNavigation: false,
        // Only the active module's content is built here — unlike an
        // IndexedStack (which would build and keep every eligible module's
        // full subtree alive simultaneously, including full nested apps for
        // native-surface modules and real WebViews), this matches the
        // desktop branch above and builds one module at a time.
        child: mobileModules.isEmpty
            ? const SizedBox.shrink()
            : PageTransitionSwitcher(
                transitionBuilder: (child, animation, secondaryAnimation) =>
                    FadeThroughTransition(
                      animation: animation,
                      secondaryAnimation: secondaryAnimation,
                      child: child,
                    ),
                child: KeyedSubtree(
                  key: ValueKey<String>(
                    '$currentServerKey:${mobileActiveModule!.id}',
                  ),
                  child: buildModuleChild(
                    context,
                    ref,
                    _workspace,
                    mobileActiveModule,
                    sessionsByModuleId,
                    workspaceHeaderAction: showMobileInlineServerControl
                        ? InlineServerConnectionControl(
                            onPressed: () =>
                                showServerConnectionPopup(context, ref),
                            iconOnly: true,
                          )
                        : null,
                  ),
                ),
              ),
      );
    }

    final activeModule = eligibleModules[clampedIndex];
    final activeSession = sessionsByModuleId[activeModule.id];
    final activeModuleIsReady =
        activeModule.status == ModuleStatus.running ||
        activeModule.status == ModuleStatus.degraded;
    final showInlineServerControl =
        activeModule.id == 'neurocnl' &&
        activeModuleIsReady &&
        activeSession?.surfaceMode == 'native';

    return Scaffold(
      backgroundColor: tokens.shellBackground,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: PageTransitionSwitcher(
                transitionBuilder: (child, animation, secondaryAnimation) =>
                    FadeThroughTransition(
                      animation: animation,
                      secondaryAnimation: secondaryAnimation,
                      child: child,
                    ),
                child: KeyedSubtree(
                  key: ValueKey<String>('$currentServerKey:$desiredModuleId'),
                  child: buildModuleChild(
                    context,
                    ref,
                    _workspace,
                    activeModule,
                    sessionsByModuleId,
                    workspaceHeaderAction: showInlineServerControl
                        ? _buildInlineServerConnectionControl(context)
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
