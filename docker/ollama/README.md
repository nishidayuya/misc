# Ollama playground

play Ollama

## Setup

Generate a secret key for SearXNG:

```console
$ echo "SEARXNG_SECRET=$(openssl rand -hex 32)" >> .env
```

## CPU only mode

```console
$ docker compose up -d &&
    docker compose exec ollama ollama run llama3.2 'hi, who are you?'
```

## NVIDIA GPU mode

Install [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) on the host and configure Docker to use it:

```console
$ sudo nvidia-ctk runtime configure --runtime=docker &&
    sudo systemctl restart docker
```

Then stack `docker-compose.nvidia-gpu.yml` on `docker-compose.yml`:

```console
$ export COMPOSE_FILE=docker-compose.yml:docker-compose.nvidia-gpu.yml
$ docker compose up -d &&
    docker compose exec ollama ollama run llama3.2 'hi, who are you?'
```

`docker compose exec ollama ollama ps` shows `100% GPU` in the `PROCESSOR` column when the model runs on the GPU.

## Web search for Claude Code

Claude Code's built-in WebSearch tool runs on Anthropic's API, so it does not work when Claude Code talks to Ollama.
Instead, `docker compose up -d` also starts [SearXNG](https://docs.searxng.org/) (a metasearch engine) and [mcp-searxng](https://github.com/ihor-sokoliuk/mcp-searxng) (an MCP server for it).
The MCP endpoint listens on `http://127.0.0.1:3000/mcp` (change with `MCP_SEARXNG_PORT`).

Pass `claude-mcp.json` to Claude Code (set `MCP_SEARXNG_URL` if the endpoint is not `http://127.0.0.1:3000`):

```console
$ export ANTHROPIC_BASE_URL=http://127.0.0.1:11434 ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_API_KEY=
$ claude --model gpt-oss:20b \
    --mcp-config /path/to/docker/ollama/claude-mcp.json \
    --disallowedTools WebSearch
```

Search engines are configured in `searxng/settings.yml`.
Engines may reject requests with rate limits or CAPTCHAs, so several of them are enabled.

## References

- [ollama/ollama - Docker Image | Docker Hub](https://hub.docker.com/r/ollama/ollama)
- [Ollama library](https://ollama.com/library)
- [searxng/searxng - Docker Image | Docker Hub](https://hub.docker.com/r/searxng/searxng)
- [isokoliuk/mcp-searxng - Docker Image | Docker Hub](https://hub.docker.com/r/isokoliuk/mcp-searxng)
