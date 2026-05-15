# 04: Report Generation

Once all benchmarks, robustness tests, and hardware comparisons are complete, the data must be synthesized into a deployable artifact.

## Report Screen

The `report_screen` orchestrates this final step.

### Report Builder
- **Visual:** A configuration panel (`report_builder`).
- **Usage:** Allows the user to select which benchmarks, charts, and diff tables to include in the final document.
- **Export Formats:** Reports can typically be exported to PDF, Markdown, or JSON for automated compliance checks.

## Importance for Documentation
- **Humans:** Use this to generate a "spec sheet" for the neural network before handing it off to the embedded firmware team.
- **AI Agents:** If an agent is tasked with a complete design lifecycle, generating and saving a JSON report via the Report Builder's backend API is the final verification step to prove the task was completed successfully.
