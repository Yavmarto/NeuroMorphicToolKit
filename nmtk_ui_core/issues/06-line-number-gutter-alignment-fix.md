# Fix Line-Number Gutter Alignment With Editor Text Lines

## Owner

- `M2` Single-repo cloud agent or local module owner

## Depends on

- `neurocnl/issues/11-neurocnl-shell-adapter-and-editor-workspace.md`

## Can run in parallel with

- `nmtk_ui_core/issues/05-validation-ux-improvements.md`

## Write scope

- `neurocnl/frontend/lib/widgets/` (CNL editor widget)
- `neurocnl/frontend/test/`

## Background

The line-number gutter in the CNL editor does not stay in sync with the text lines. Known
symptoms:
- Line numbers shift when the editor has wrapped lines (a single logical CNL line wraps
  visually onto multiple display rows).
- Line numbers do not update correctly after inserting or deleting lines mid-document.
- On some zoom levels the gutter and text baselines are misaligned by a fraction of a pixel,
  making it look slightly off.

## Tasks

- Audit the current line-number rendering implementation in the CNL editor widget (likely
  `cnl_editor.dart` or an equivalent `CodeField`/`CodeController`-based widget).
- Ensure line-number height is derived from the **actual text line metrics** (using
  `TextPainter` or the code-field library's line height callback) rather than a hardcoded
  constant.
- Handle wrapped lines: a line with visual wrap should show the line number only at the first
  visual row; subsequent wrapped rows show no number (standard editor behaviour).
- Ensure line numbers update synchronously on insert/delete (no off-by-one after newline
  insertion).
- Add a widget test that renders 20 lines of CNL, retrieves the `Rect` of line-number labels
  and the corresponding text rows, and asserts vertical alignment within 1 logical pixel.

## Done when

- Line numbers align with text at all zoom levels available in the app.
- Inserting a newline in the middle of the document renumbers all subsequent lines correctly.
- Wrapped lines do not cause duplicate or shifted numbers.
- Widget test asserting alignment passes.

## Validation

- `cd neurocnl/frontend && flutter test`
- Manual: open a long CNL file (> 50 lines), resize the editor pane to cause wrapping →
  confirm numbers stay aligned.
