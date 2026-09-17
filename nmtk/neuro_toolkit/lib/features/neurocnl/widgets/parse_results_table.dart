import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/loading_shimmer.dart';

/// Table showing parsed CNL sentences with their concept, subject, action.
///
/// Part of Epic 2: Visual Pipeline — parse results panel.
class ParseResultsTable extends ConsumerWidget {
  const ParseResultsTable({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipeline = ref.watch(pipelineProvider);
    final parseResult = pipeline.parseResult;

    if (pipeline.parseStatus == StepStatus.running) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, _) => LoadingShimmer.listTile(),
      );
    }

    return parseResult == null
        ? const _EmptyState(
            icon: Icons
                .text_snippet_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            message:
                'Parse results will appear here once you write or load a spec.',
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: _buildHeader(context, parseResult),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: parseResult.sentences.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _ParseRow(sentence: parseResult.sentences[index]);
                  },
                ),
              ),
            ],
          );
  }

  Widget _buildHeader(BuildContext context, ParseResult result) {
    final ok = result.errors == 0;
    return NmtkStatusBanner(
      title: ok
          ? 'All ${result.total} sentences parsed successfully'
          : '${result.errors} parse error${result.errors == 1 ? '' : 's'} — ${result.total - result.errors}/${result.total} sentences valid',
      tone: ok ? NmtkTone.success : NmtkTone.danger,
      icon: ok ? ZetaIcons.check_circle_outline : ZetaIcons.cancel_outline,
    );
  }
}

class _ParseRow extends StatelessWidget {
  final ParseSentence sentence;

  const _ParseRow({required this.sentence});

  @override
  Widget build(BuildContext context) {
    final healthyColor = Zeta.of(context).colors.mainPositive;
    final errorColor = Zeta.of(context).colors.mainNegative;
    final parsed = sentence.parsed;
    final errorDetail = sentence.errorDetail;
    final primaryError = errorDetail?.primaryMessage ?? sentence.error;

    // zeta-card-reduction Task 9: NmtkItemCard → ZetaListItem.
    // Same pattern as the validation panel's failure rows
    // (validation_panel.dart line 396 + 520) — `title: Column(...)`
    // hosts the rich body content (raw sentence + parsed tags + error
    // message + hint + examples). The NmtkItemCard tone-based left-edge
    // accent is dropped; invalid rows are still distinguishable via the
    // red trailing icon and red error text in the body.
    return ZetaListItem(
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Zeta.of(context).colors.surfaceHover),
        child: Text(
          'L${sentence.line}',
          style: Zeta.of(context).textStyles.bodySmall.copyWith(
            color: Zeta.of(context).colors.mainSubtle,
          ),
        ),
      ),
      trailing: Icon(
        sentence.valid ? ZetaIcons.check_circle : ZetaIcons.close,
        size: 16,
        color: sentence.valid ? healthyColor : errorColor,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Raw sentence text
          Text(
            sentence.raw,
            style: Zeta.of(context).textStyles.bodySmall.copyWith(
              color: sentence.valid
                  ? Zeta.of(context).colors.mainDefault
                  : errorColor,
            ),
          ),
          // Parsed details
          if (parsed != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _Tag(
                  label: 'Subject',
                  value: parsed.subject,
                  color: Zeta.of(context).colors.mainDefault,
                ),
                _Tag(
                  label: 'Concept',
                  value: parsed.concept,
                  color: Zeta.of(context).colors.mainPrimary,
                ),
                _Tag(
                  label: 'Action',
                  value: parsed.action,
                  color: Zeta.of(context).colors.mainDefault,
                ),
                if (parsed.condition != null)
                  _Tag(
                    label: 'Condition',
                    value: parsed.condition!,
                    color: Zeta.of(context).colors.mainPrimary,
                  ),
                if (parsed.negated)
                  _Tag(label: 'Negated', value: 'yes', color: errorColor),
              ],
            ),
          ],
          // Error message
          if (primaryError != null) ...[
            const SizedBox(height: 8),
            Text(
              primaryError,
              style: Zeta.of(
                context,
              ).textStyles.bodySmall.copyWith(color: errorColor),
            ),
            if (errorDetail?.hint != null) ...[
              const SizedBox(height: 8),
              Text(
                errorDetail!.hint!,
                style: Zeta.of(context).textStyles.bodySmall.copyWith(
                  color: Zeta.of(context).colors.mainSubtle,
                ),
              ),
            ],
            if (errorDetail != null && errorDetail.examples.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Examples',
                style: Zeta.of(context).textStyles.bodySmall.copyWith(
                  color: Zeta.of(context).colors.mainSubtle,
                ),
              ),
              const SizedBox(height: 8),
              ...errorDetail.examples
                  .take(2)
                  .map(
                    (example) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        example,
                        style: Zeta.of(context).textStyles.bodySmall.copyWith(
                          color: Zeta.of(context).colors.mainSubtle,
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Tag({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: Zeta.of(context).textStyles.bodySmall.copyWith(
                color: Zeta.of(context).colors.mainSubtle,
              ),
            ),
            TextSpan(
              text: value,
              style: Zeta.of(
                context,
              ).textStyles.bodySmall.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: Zeta.of(context).colors.mainSubtle.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
            ),
          ),
        ],
      ),
    );
  }
}
