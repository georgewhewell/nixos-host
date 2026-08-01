"""Provider registry."""

from .anthropic import AnthropicProvider
from .base import Provider
from .gemini import GeminiProvider
from .grok import GrokProvider
from .kimi import KimiProvider
from .openai_codex import OpenAICodexProvider

PROVIDERS: dict[str, type[Provider]] = {
    provider.name: provider
    for provider in (
        AnthropicProvider,
        OpenAICodexProvider,
        GeminiProvider,
        GrokProvider,
        KimiProvider,
    )
}

__all__ = ["PROVIDERS", "Provider"]
