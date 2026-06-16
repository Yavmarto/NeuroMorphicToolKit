# nmtk_ui_core

Read first:
- `../CODING_STYLE_GUIDE.md`
- `pubspec.yaml`
- `analysis_options.yaml`
- `docs/ADR-Gemini/0001-initial-architecture.md`
- `docs/ADR-claude/0001-barrel-export-pattern.md`
- `docs/ADR-claude/0003-zero-state-management-dependency.md`
- `docs/ADR-claude/0004-domain-specific-widget-library.md`

Constraints:
- `lib/nmtk_ui_core.dart` is the public API barrel; add or remove public models, theme exports, and widgets there intentionally.
- This package must stay state-management-agnostic. Keep runtime dependencies limited to Flutter core plus the package's declared UI dependencies; use callback-based APIs instead of Provider or Riverpod bindings.
- Shared widgets must remain self-contained and typed. If a widget needs app services, routing, HTTP clients, or module-specific state, it belongs in the consumer app instead.
- When a shared model changes, update every consumer package that imports it before treating the change as complete.
- Verify touched surfaces with `flutter test`.

Do NOT:
- Import `provider`, `flutter_riverpod`, or module-specific app code here.
- Expose a new public widget without adding it to the barrel export.
- Hide network calls, environment lookups, or launcher state inside a shared widget.

<directory_structure>
├── AGENTS.md
├── CHANGELOG.md
├── LICENSE
├── README.md
├── analysis_options.yaml
├── assets
│   └── fonts
│       ├── JetBrainsMono-VariableFont_wght.ttf
│       └── SpaceGrotesk-VariableFont_wght.ttf
├── dart_test.yaml
├── devtools_options.yaml
├── docs
│   ├── ADR-Gemini
│   │   └── 0001-initial-architecture.md
│   ├── ADR-claude
│   │   ├── 0001-barrel-export-pattern.md
│   │   ├── 0002-material-design-3-theming.md
│   │   ├── 0003-zero-state-management-dependency.md
│   │   └── 0004-domain-specific-widget-library.md
│   ├── item_card.md
│   └── section_header.md
├── issues
│   └── 08-auto-aligning-pipeline-strip-primitive.md
├── issues-archive
│   ├── 001-add-dartdoc-comments.md
│   ├── 001-poc-expand-widget-test-coverage.md
│   ├── 01-shell-tokens-top-bars-and-status-primitives.md
│   ├── 02-modules-surface-cards-and-utility-panel-patterns.md
│   ├── 03-shell-chrome-overhaul.md
│   ├── 04-loading-screen-backend-readiness.md
│   ├── 05-validation-ux-improvements.md
│   ├── 06-line-number-gutter-alignment-fix.md
│   ├── 07-animation-polish-motion-system.md
│   └── NMTK-21-nmtk-ui-core.md
├── lib
│   ├── app_theme.dart
│   ├── models
│   │   ├── akida_deployment_model.dart
│   │   ├── commands.dart
│   │   ├── energy_report.dart
│   │   ├── host_navigation_models.dart
│   │   ├── pynq_deployment_model.dart
│   │   ├── quantization_report.dart
│   │   ├── scaffold_models.dart
│   │   ├── sensor_frame.dart
│   │   ├── shell_models.dart
│   │   └── teensy_deployment_model.dart
│   ├── motion_tokens.dart
│   ├── neat
│   │   ├── dark
│   │   │   ├── attendance.dart
│   │   │   ├── customer.dart
│   │   │   ├── cut
│   │   │   │   ├── activities_card.dart
│   │   │   │   ├── activity_type_card.dart
│   │   │   │   ├── amount_display.dart
│   │   │   │   ├── announcement_card.dart
│   │   │   │   ├── attendance_check_in_card.dart
│   │   │   │   ├── attendance_recap_card.dart
│   │   │   │   ├── attendance_stat_row.dart
│   │   │   │   ├── attendance_summary.dart
│   │   │   │   ├── avg_sales_card.dart
│   │   │   │   ├── bill_card.dart
│   │   │   │   ├── billing_toggle.dart
│   │   │   │   ├── calories_card.dart
│   │   │   │   ├── chart_legend_row.dart
│   │   │   │   ├── choose_plan_button.dart
│   │   │   │   ├── customer_growth_card.dart
│   │   │   │   ├── customer_message_card.dart
│   │   │   │   ├── customer_metric_card.dart
│   │   │   │   ├── customer_social_stat_card.dart
│   │   │   │   ├── customer_widgets.dart
│   │   │   │   ├── dark_card.dart
│   │   │   │   ├── dark_card_header.dart
│   │   │   │   ├── dark_status_bar.dart
│   │   │   │   ├── dark_top_bar.dart
│   │   │   │   ├── download_chip.dart
│   │   │   │   ├── elearning_attendance_card.dart
│   │   │   │   ├── elearning_widgets.dart
│   │   │   │   ├── event_card.dart
│   │   │   │   ├── event_widgets.dart
│   │   │   │   ├── exercise_type_row.dart
│   │   │   │   ├── filter_chip.dart
│   │   │   │   ├── finance_widgets.dart
│   │   │   │   ├── flow_card.dart
│   │   │   │   ├── gain_weight_card.dart
│   │   │   │   ├── health_legend_item.dart
│   │   │   │   ├── health_metric_card.dart
│   │   │   │   ├── health_widgets.dart
│   │   │   │   ├── income_card.dart
│   │   │   │   ├── ips_graph_card.dart
│   │   │   │   ├── material_file_row.dart
│   │   │   │   ├── message_row.dart
│   │   │   │   ├── new_material_card.dart
│   │   │   │   ├── office_card.dart
│   │   │   │   ├── office_widgets.dart
│   │   │   │   ├── outcome_card.dart
│   │   │   │   ├── outcome_row.dart
│   │   │   │   ├── overview_chart_card.dart
│   │   │   │   ├── overview_spend_row.dart
│   │   │   │   ├── overview_widgets.dart
│   │   │   │   ├── oximeter_card.dart
│   │   │   │   ├── oximeter_value.dart
│   │   │   │   ├── popular_products_card.dart
│   │   │   │   ├── pricing_header_card.dart
│   │   │   │   ├── pricing_tier_card.dart
│   │   │   │   ├── product_row.dart
│   │   │   │   ├── product_views_card.dart
│   │   │   │   ├── products_widgets.dart
│   │   │   │   ├── progress_card.dart
│   │   │   │   ├── project_row.dart
│   │   │   │   ├── project_small_count_card.dart
│   │   │   │   ├── project_widgets.dart
│   │   │   │   ├── projects_completed_card.dart
│   │   │   │   ├── quick_link_card.dart
│   │   │   │   ├── recent_projects_card.dart
│   │   │   │   ├── sales_kpi_card.dart
│   │   │   │   ├── sales_report_card.dart
│   │   │   │   ├── sales_widgets.dart
│   │   │   │   ├── sks_card.dart
│   │   │   │   ├── spirometry_card.dart
│   │   │   │   ├── statistic_row.dart
│   │   │   │   ├── statistics_card.dart
│   │   │   │   ├── status_badge.dart
│   │   │   │   ├── student_assignment_card.dart
│   │   │   │   ├── student_profile_card.dart
│   │   │   │   ├── student_widgets.dart
│   │   │   │   ├── target_card.dart
│   │   │   │   ├── task_row.dart
│   │   │   │   ├── temp_log_row.dart
│   │   │   │   ├── today_schedule_card.dart
│   │   │   │   ├── today_tasks_card.dart
│   │   │   │   ├── tracker_small_stat_card.dart
│   │   │   │   ├── tracker_widgets.dart
│   │   │   │   ├── transaction_history_card.dart
│   │   │   │   ├── transaction_row.dart
│   │   │   │   ├── upgrade_widgets.dart
│   │   │   │   ├── weekly_calendar_card.dart
│   │   │   │   ├── weekly_day_column.dart
│   │   │   │   ├── weight_progress_section.dart
│   │   │   │   ├── weight_stat.dart
│   │   │   │   ├── workout_overview_card.dart
│   │   │   │   ├── workout_stat.dart
│   │   │   │   ├── workout_stat_item.dart
│   │   │   │   ├── workout_stats_card.dart
│   │   │   │   ├── workout_widgets.dart
│   │   │   │   └── workspace_header.dart
│   │   │   ├── elearning.dart
│   │   │   ├── event.dart
│   │   │   ├── finance.dart
│   │   │   ├── health.dart
│   │   │   ├── office.dart
│   │   │   ├── overview.dart
│   │   │   ├── products.dart
│   │   │   ├── project.dart
│   │   │   ├── sales.dart
│   │   │   ├── student.dart
│   │   │   ├── tracker.dart
│   │   │   ├── upgrade.dart
│   │   │   └── workout.dart
│   │   ├── dark2
│   │   └── light
│   ├── nmtk_ui_core.dart
│   ├── shell_tokens.dart
│   ├── widgets
│   │   ├── adaptive_layout.dart
│   │   ├── akida_support_state_card.dart
│   │   ├── backend_support_banner.dart
│   │   ├── buttons.dart
│   │   ├── command_palette.dart
│   │   ├── desktop_scaffold.dart
│   │   ├── empty_state.dart
│   │   ├── energy_bar_chart.dart
│   │   ├── error_card.dart
│   │   ├── host_navigation_scope.dart
│   │   ├── info_chip.dart
│   │   ├── key_value_row.dart
│   │   ├── loading_screen.dart
│   │   ├── mobile_bottom_bar.dart
│   │   ├── mobile_scaffold.dart
│   │   ├── nmtk_navigation_rail.dart
│   │   ├── pipeline_stepper.dart
│   │   ├── progress_card.dart
│   │   ├── pynq_deploy_status_card.dart
│   │   ├── quantization_table.dart
│   │   ├── result_card.dart
│   │   ├── section_card.dart
│   │   ├── section_header.dart
│   │   ├── shell_chrome_scope.dart
│   │   ├── shell_readiness_state_view.dart
│   │   ├── shell_status_badge.dart
│   │   ├── shortcut_scope.dart
│   │   ├── snack_bars.dart
│   │   ├── snn_workflow_stepper.dart
│   │   ├── sparkline_chart.dart
│   │   ├── status_badge.dart
│   │   ├── status_banner.dart
│   │   ├── summary_card.dart
│   │   ├── surface_card.dart
│   │   ├── toasts.dart
│   │   ├── tone.dart
│   │   ├── top_app_bar.dart
│   │   ├── validation_chip.dart
│   │   ├── workflow_card.dart
│   │   ├── workflow_step_row.dart
│   │   ├── workspace_overview_card.dart
│   │   ├── workspace_shell.dart
│   │   └── workspace_switcher_bar.dart
│   └── zeta_theme.dart
├── pubspec.lock
├── pubspec.yaml
└── test
    ├── adaptive_layout_test.dart
    ├── buttons_test.dart
    ├── command_palette_test.dart
    ├── desktop_scaffold_test.dart
    ├── energy_bar_chart_test.dart
    ├── governance
    │   └── material_icons_audit_test.dart
    ├── host_navigation_scope_test.dart
    ├── loading_screen_test.dart
    ├── migration_properties_test.dart
    ├── models
    │   └── icon_resolution_test.dart
    ├── models_test.dart
    ├── motion_tokens_test.dart
    ├── nmtk_navigation_rail_test.dart
    ├── pipeline_stepper_test.dart
    ├── pynq_deploy_status_card_test.dart
    ├── quantization_table_test.dart
    ├── responsive_scaffold_test.dart
    ├── shared_shell_widgets_test.dart
    ├── shell_primitives_test.dart
    ├── snack_bars_test.dart
    ├── sparkline_chart_test.dart
    ├── theme_test.dart
    ├── widgets
    │   ├── goldens
    │   ├── section_header_test.dart
    │   ├── status_banner_test.dart
    │   └── surface_card_nesting_assert_test.dart
    ├── workflow_card_test.dart
    └── workspace_shell_test.dart
</directory_structure>
