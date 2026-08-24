part of '../environment_editor.dart';

class _ImportResult {
  const _ImportResult(this.name, this.requirements);
  final String name;
  final String requirements;
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _reqController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _reqController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NmtkContentDialog(
      title: 'Import requirements',
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Environment name',
                style: Zeta.of(context).textStyles.labelMedium),
            SizedBox(height: context.nmtkTokens.compactGap),
            NmtkTextInput(
              controller: _nameController,
              placeholder: 'e.g. Shared experiment',
            ),
            SizedBox(height: context.nmtkTokens.sectionGap),
            Text('requirements.txt',
                style: Zeta.of(context).textStyles.labelMedium),
            SizedBox(height: context.nmtkTokens.compactGap),
            NmtkCodeTextArea(
              controller: _reqController,
              minLines: 6,
              maxLines: 12,
              hintText: 'numpy==1.26.0\ncowsay==6.1\n…',
            ),
          ],
        ),
      ),
      actions: [
        ZetaButton.text(
          onPressed: () => Navigator.pop(context),
          label: 'Cancel',
        ),
        ZetaButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _ImportResult(name, _reqController.text),
            );
          },
          label: 'Import',
        ),
      ],
    );
  }
}
