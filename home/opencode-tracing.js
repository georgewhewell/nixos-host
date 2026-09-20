// OpenCode/AI SDK owns the spans. Inject W3C context at the actual model
// fetch, when the SDK's model-call span is active; do not create a second one.
import { context } from "@otelApi@/build/src/index.js";
import { W3CTraceContextPropagator } from "@otelCore@/build/src/trace/W3CTraceContextPropagator.js";

const propagator = new W3CTraceContextPropagator();
const setter = { set: (headers, key, value) => headers.set(key, value) };

export const HellasTracing = async () => ({
  config: async (config) => {
    const provider = config.provider?.hellas;
    if (!provider) return;
    provider.options ??= {};
    const fetch = provider.options.fetch ?? globalThis.fetch;
    provider.options.fetch = (input, init) => {
      const headers = new Headers(input instanceof Request ? input.headers : undefined);
      new Headers(init?.headers).forEach((value, key) => headers.set(key, value));
      propagator.inject(context.active(), headers, setter);
      return fetch(input, { ...init, headers });
    };
  },
});
