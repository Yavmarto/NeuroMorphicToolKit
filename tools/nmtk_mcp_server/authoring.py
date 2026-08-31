from __future__ import annotations

from dataclasses import dataclass

from pydantic import BaseModel, Field

DEFAULT_GRAMMAR_URI = "nmtk://cnl/grammar/current"
DEFAULT_SUPPORT_MATRIX_URI = "nmtk://cnl/support-matrix/current"
DEFAULT_CAVEAT = (
    "Guide excerpts are copied from canonical resources only; no backend or hardware "
    "support is inferred."
)


class AuthoringGuideSection(BaseModel):
    title: str
    source_uri: str
    excerpt: str
    level: int = 1
    matched_topic: bool = False


class AuthoringGuide(BaseModel):
    topic: str | None = None
    sections: list[AuthoringGuideSection] = Field(default_factory=list)
    caveats: list[str] = Field(default_factory=lambda: [DEFAULT_CAVEAT])


@dataclass(frozen=True)
class _MarkdownSection:
    title: str
    level: int
    body: str


def build_authoring_guide(
    *,
    grammar_text: str,
    support_matrix_text: str,
    topic: str | None = None,
    grammar_uri: str = DEFAULT_GRAMMAR_URI,
    support_matrix_uri: str = DEFAULT_SUPPORT_MATRIX_URI,
    max_sections_per_source: int = 2,
    max_chars_per_section: int = 1200,
) -> AuthoringGuide:
    """Build a bounded authoring guide from canonical resource text only."""
    normalized_topic = _normalize_topic(topic)
    grammar_sections = _select_sections(
        _parse_markdown_sections(grammar_text),
        topic=normalized_topic,
        max_sections=max_sections_per_source,
    )
    support_sections = _select_sections(
        _parse_markdown_sections(support_matrix_text),
        topic=normalized_topic,
        max_sections=max_sections_per_source,
    )

    return AuthoringGuide(
        topic=normalized_topic,
        sections=[
            *_to_guide_sections(
                grammar_sections,
                source_uri=grammar_uri,
                topic=normalized_topic,
                max_chars=max_chars_per_section,
            ),
            *_to_guide_sections(
                support_sections,
                source_uri=support_matrix_uri,
                topic=normalized_topic,
                max_chars=max_chars_per_section,
            ),
        ],
    )


def _normalize_topic(topic: str | None) -> str | None:
    if topic is None:
        return None
    stripped = topic.strip().lower()
    return stripped or None


def _parse_markdown_sections(text: str) -> list[_MarkdownSection]:
    sections: list[_MarkdownSection] = []
    current_title = "Document"
    current_level = 1
    current_lines: list[str] = []

    for line in text.splitlines():
        heading = _parse_heading(line)
        if heading is not None:
            if current_lines or sections:
                sections.append(
                    _MarkdownSection(
                        title=current_title,
                        level=current_level,
                        body="\n".join(current_lines).strip(),
                    )
                )
            current_level, current_title = heading
            current_lines = []
            continue
        current_lines.append(line)

    if current_lines or not sections:
        sections.append(
            _MarkdownSection(
                title=current_title,
                level=current_level,
                body="\n".join(current_lines).strip(),
            )
        )
    return sections


def _parse_heading(line: str) -> tuple[int, str] | None:
    stripped = line.strip()
    if not stripped.startswith("#"):
        return None
    marker, _, title = stripped.partition(" ")
    if not title or any(char != "#" for char in marker):
        return None
    return len(marker), title.strip()


def _select_sections(
    sections: list[_MarkdownSection],
    *,
    topic: str | None,
    max_sections: int,
) -> list[_MarkdownSection]:
    if topic is not None:
        matches = [
            section
            for section in sections
            if topic in section.title.lower() or topic in section.body.lower()
        ]
        if matches:
            return matches[:max_sections]
    return [section for section in sections if section.body][:max_sections]


def _to_guide_sections(
    sections: list[_MarkdownSection],
    *,
    source_uri: str,
    topic: str | None,
    max_chars: int,
) -> list[AuthoringGuideSection]:
    return [
        AuthoringGuideSection(
            title=section.title,
            source_uri=source_uri,
            excerpt=_bounded_excerpt(section.body, max_chars=max_chars),
            level=section.level,
            matched_topic=(
                topic is not None
                and (topic in section.title.lower() or topic in section.body.lower())
            ),
        )
        for section in sections
    ]


def _bounded_excerpt(text: str, *, max_chars: int) -> str:
    normalized = "\n".join(line.rstrip() for line in text.strip().splitlines()).strip()
    if len(normalized) <= max_chars:
        return normalized
    if max_chars <= 1:
        return normalized[:max_chars]
    return f"{normalized[: max_chars - 1].rstrip()}…"
