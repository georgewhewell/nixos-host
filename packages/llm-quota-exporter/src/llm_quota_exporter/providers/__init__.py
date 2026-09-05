"""Provider registry."""

from .anthropic import AnthropicProvider
from .base import Provider
from .deepseek import DeepSeekProvider
from .gemini import GeminiProvider
from .grok import GrokProvider
from .kimi import KimiProvider
from .openai_codex import OpenAICodexProvider
from .openrouter import OpenRouterProvider

PROVIDERS: dict[str, type[Provider]] = {
    provider.name: provider
    for provider in (
        AnthropicProvider,
        OpenAICodexProvider,
        GeminiProvider,
        GrokProvider,
        KimiProvider,
        OpenRouterProvider,
        DeepSeekProvider,
    )
}

__all__ = ["PROVIDERS", "Provider"]
