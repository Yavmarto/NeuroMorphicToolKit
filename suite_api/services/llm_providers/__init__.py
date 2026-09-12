"""Desktop LLM provider adapters for the Studio assistant."""

from suite_api.services.llm_providers.base import (
    LlmChatResult,
    LlmProvider,
    ProviderProbe,
)
from suite_api.services.llm_providers.lmstudio import LmStudioProvider
from suite_api.services.llm_providers.ollama import OllamaProvider
from suite_api.services.llm_providers.registry import (
    all_providers,
    probe_all,
    resolve_active_provider,
    reset_providers_for_tests,
    studio_agent_tool_schemas,
)
from suite_api.services.llm_providers.subprocess_cli import SubprocessCliProvider

__all__ = [
    "LmStudioProvider",
    "LlmChatResult",
    "LlmProvider",
    "OllamaProvider",
    "ProviderProbe",
    "SubprocessCliProvider",
    "all_providers",
    "probe_all",
    "resolve_active_provider",
    "reset_providers_for_tests",
    "studio_agent_tool_schemas",
]
