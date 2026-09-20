# Adapt OpenCode 1.18's native AI SDK spans to the GenAI Development
# conventions (c88d504ab3d9879f8e50d3cc87e69775e11db234). No extra spans or
# span-derived metrics: the outer SDK operation owns client usage; its inner
# attempts retain their identity/parentage without a second GenAI operation.
{
  error_mode = "propagate";
  trace_statements = [
    {
      context = "span";
      conditions = [ ''resource.attributes["service.name"] == "opencode" and span.name == "ai.streamText"'' ];
      statements = [
        ''set(span.attributes["gen_ai.operation.name"], "chat")''
        ''set(span.attributes["gen_ai.provider.name"], span.attributes["ai.model.provider"])''
        ''replace_pattern(span.attributes["gen_ai.provider.name"], "[.]chat$", "") where span.attributes["gen_ai.provider.name"] != nil''
        ''set(span.attributes["gen_ai.request.model"], span.attributes["ai.model.id"])''
        ''set(span.attributes["gen_ai.response.model"], span.attributes["ai.response.model"])''
        ''set(span.attributes["gen_ai.response.id"], span.attributes["ai.response.id"])''
        ''set(span.attributes["gen_ai.conversation.id"], span.attributes["session.id"])''
        ''set(span.attributes["gen_ai.request.stream"], true)''
        ''set(span.attributes["gen_ai.request.max_tokens"], span.attributes["ai.settings.maxOutputTokens"])''
        ''set(span.attributes["gen_ai.request.temperature"], span.attributes["ai.settings.temperature"])''
        ''set(span.attributes["gen_ai.request.top_p"], span.attributes["ai.settings.topP"])''
        ''set(span.attributes["gen_ai.usage.input_tokens"], span.attributes["ai.usage.inputTokens"])''
        ''set(span.attributes["gen_ai.usage.output_tokens"], span.attributes["ai.usage.outputTokens"])''
        ''set(span.attributes["gen_ai.usage.cache_read.input_tokens"], span.attributes["ai.usage.cachedInputTokens"])''
        ''set(span.attributes["gen_ai.response.finish_reasons"], [span.attributes["ai.response.finishReason"]]) where span.attributes["ai.response.finishReason"] != nil''
        ''set(span.attributes["error.type"], "inference_error") where span.status.code == STATUS_CODE_ERROR''
        ''set(span.kind, SPAN_KIND_CLIENT)''
        ''set(span.name, "chat")''
        ''set(span.name, Concat(["chat", span.attributes["gen_ai.request.model"]], " ")) where span.attributes["gen_ai.request.model"] != nil''
      ];
    }
    {
      context = "span";
      conditions = [ ''resource.attributes["service.name"] == "opencode" and span.name == "ai.streamText.doStream"'' ];
      statements = [ ''delete_matching_keys(span.attributes, "^gen_ai[.]")'' ];
    }
    {
      context = "span";
      conditions = [ ''resource.attributes["service.name"] == "opencode" and span.name == "ai.toolCall"'' ];
      statements = [
        ''set(span.attributes["gen_ai.operation.name"], "execute_tool")''
        ''set(span.attributes["gen_ai.tool.name"], span.attributes["ai.toolCall.name"])''
        ''set(span.attributes["gen_ai.tool.call.id"], span.attributes["ai.toolCall.id"])''
        ''set(span.kind, SPAN_KIND_INTERNAL)''
        ''set(span.name, "execute_tool")''
        ''set(span.name, Concat(["execute_tool", span.attributes["gen_ai.tool.name"]], " ")) where span.attributes["gen_ai.tool.name"] != nil''
      ];
    }
    {
      context = "span";
      conditions = [ ''resource.attributes["service.name"] == "opencode"'' ];
      statements = [
        # OpenCode does not expose AI SDK recordInputs/recordOutputs switches.
        # Remove content, tool arguments/results and request headers locally,
        # before forwarding to the remote trace backend. Keep metadata only.
        ''keep_keys(span.attributes, ["gen_ai.operation.name", "gen_ai.provider.name", "gen_ai.request.model", "gen_ai.response.model", "gen_ai.response.id", "gen_ai.conversation.id", "gen_ai.request.stream", "gen_ai.request.max_tokens", "gen_ai.request.temperature", "gen_ai.request.top_p", "gen_ai.usage.input_tokens", "gen_ai.usage.output_tokens", "gen_ai.usage.cache_read.input_tokens", "gen_ai.response.finish_reasons", "gen_ai.tool.name", "gen_ai.tool.call.id", "session.id", "error.type", "http.request.method", "http.response.status_code", "http.route", "server.address", "server.port"])''
        ''set(span.status.message, "")''
      ];
    }
    {
      context = "spanevent";
      conditions = [ ''resource.attributes["service.name"] == "opencode"'' ];
      statements = [ ''keep_keys(spanevent.attributes, [])'' ];
    }
  ];
}
