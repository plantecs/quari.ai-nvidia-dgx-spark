# Quari.ai DGX Spark LLM Stack

Enterprise-ready deployment of **gpt-oss:120b** on NVIDIA DGX Spark, delivered by **plantecs.ai** (R&D) and **quari.ai** (dedicated AI servers). The stack bundles high-throughput TensorRT-LLM inference, an OpenAI-compatible proxy with context trimming, AnythingLLM as the multi-user UI, and HTTPS termination with automatic certificates.

## Components
- TensorRT-LLM `trtllm-serve` (PyTorch backend) running `openai/gpt-oss-120b`
- FastAPI proxy (`trtllm-proxy`) that trims oldest messages to fit the context window and returns token-usage metadata
- AnythingLLM frontend (generic OpenAI provider)
- Nginx reverse proxy with HTTPS; Let’s Encrypt automation via Certbot; self-signed fallback
- Persistent model/cache volumes so weights survive container restarts

## Prerequisites
- NVIDIA DGX Spark (A100/H100) with recent NVIDIA drivers
- Docker + Docker Compose v2
- Outbound internet for image/model downloads; inbound 80/443 reachable for Let’s Encrypt issuance
- NVIDIA NGC API key (https://ngc.nvidia.com/setup/api-key)

## One-command bootstrap
Use the init helper to pull the latest repo and run the setup script:

```bash
sudo /root/init_llm_server.sh
```

What it does:
1) Prompts for the fully qualified hostname (used for TLS and service URLs)
2) Clones/updates `quari.ai-nvidia-dgx-spark` and runs `tensorrt_gpt-oss:120b_anythingllm_nginx.sh` (fallback to `setup_llm.sh`)
3) Generates env files, proxy, nginx config, volumes, and starts the stack

## Key settings (defaults)
- Context window enforced by proxy/TRT: 81,696 tokens; max response tokens: 2,000 (trimmed oldest-first if over limit)
- GPU KV cache headroom: `--kv_cache_free_gpu_memory_fraction 0.95`
- Batch size: 1 (single concurrent prompt per request)
- Ports: TRT-LLM 8000 (localhost), proxy 7000 (localhost), AnythingLLM via HTTPS 443

## HTTPS and certificates
- Self-signed cert generated automatically for immediate access
- Certbot issues/renews real certificates for the provided hostname using webroot challenge
- Certs stored in `nginx/certs`; nginx is HUPed after renewal

## Persistence
- Model and tokenizer cache: `trtllm_cache` → `/workspace/.cache`
- AnythingLLM data: `anythingllm_data`
- Certificates and ACME state: `nginx/certs`, `nginx/letsencrypt`, `nginx/www`

## Token trimming & observability
- Proxy logs token usage: `[proxy] original=… kept=… trimmed=… used=%`
- Responses include `proxy_token_usage` (original/kept/trimmed tokens, percent of window)
- This prevents hard crashes on overlong prompts; newest content is preserved

## Operating the stack
- Start/stop: `docker compose up -d` / `docker compose down`
- Health: `curl http://127.0.0.1:7000/health`
- Logs: `docker logs trtllm-gpt-oss-120b`, `docker logs trtllm-proxy`, `docker logs anythingllm-nginx`, `docker logs certbot`

## Support
For enterprise assistance, contact **support@quari.ai**. More about us: https://www.plantecs.ai and our dedicated server service https://www.quari.ai.
#
░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░░▒▓██████▓▒░░▒▓███████▓▒░░▒▓█▓▒░       ░▒▓██████▓▒░░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓████████▓▒░▒▓███████▓▒░░▒▓█▓▒░      ░▒▓████████▓▒░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░▒▓██▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
 ░▒▓██████▓▒░ ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░▒▓██▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
   ░▒▓█▓▒░                                                                            
    ░▒▓██▓▒░
                       quari.ai | plantecs.ai | DGX Spark LLM
