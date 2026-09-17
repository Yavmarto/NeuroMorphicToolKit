# ADR 0004: Report Generation

## Status
Accepted

## Context
Benchmark results need to be shared with stakeholders (researchers, hardware engineers, project managers) who may not have access to the API or prefer offline-readable formats.

## Decision
Generate reports using Jinja2 templates rendered to HTML, with optional PDF conversion via WeasyPrint. Charts are rendered as base64-encoded PNG images using matplotlib and embedded directly in the report. When WeasyPrint is unavailable, the system gracefully degrades to HTML-only output.

## Consequences
- **Positive:** Self-contained reports with embedded charts can be shared via email or archived; graceful degradation ensures reports work even without WeasyPrint installed.
- **Negative:** Base64-encoded charts increase report file size significantly; matplotlib rendering is synchronous and can block the event loop for complex visualizations.
