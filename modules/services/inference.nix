{ ... }:
{
  services.vllm.instances.qwen = {
    model = "Qwen/Qwen3-32B";
    port = 8000;
    host = "127.0.0.1";
    autoStart = false;
    gpuMemoryUtilization = 0.76;
    maxModelLen = 65536;
    reasoningParser = "qwen3";
    enforceEager = true;
    extraArgs = [
      "--trust-remote-code"
    ];
  };

  services.vllm.instances.deepseek = {
    model = "deepseek-ai/DeepSeek-R1-Distill-Qwen-32B";
    port = 8000;
    host = "127.0.0.1";
    autoStart = false;
    gpuMemoryUtilization = 0.76;
    maxModelLen = 65536;
    reasoningParser = "deepseek_r1";
    enforceEager = true;
    extraArgs = [
      "--trust-remote-code"
    ];
  };
}
