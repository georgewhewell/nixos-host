# One presentation and execution policy shared by the Strix fleet and gateway.
{
  name = "Qwen3.6-35B-A3B";
  contentRoot = "/mnt/Home/models/hellas/qwen3.6-35b-a3b";
  environment = "/mnt/Home/models/hellas/qwen3.6-35b-a3b/catena-wmma/model.environment";
  tokenizer = "/mnt/Home/models/hellas/qwen3.6-35b-a3b/tokenizer.json";
  chatTemplate = "qwen3.6";
  contextTokens = 32768;
  outputTokens = 4096;
  stopTokens = [ 248044 248046 ];
  execution = {
    allowed_environment = "b50578da2a2aae47d5a8c9699a059b9f0dc0e9fb91fcdb9093ee1aa74d363a6f";
    generation_policy_digest = "4bde65c88c1e8fd514d5293018aa7f4970fa72bb8980e760a3597abc52e24895";
    identity_source_digest = "01aacf5353ed8696e2aa65949543ddd62b9590f5fd7998cb5ad0c2d9e1a129ee";
    max_prompt_tokens = 32767;
    max_new_tokens = 4096;
    max_encoded_result_frame = 3 * 1024 * 1024;
  };
}
