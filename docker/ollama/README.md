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

## Context length and VRAM

Claude Code needs a long context (32k tokens or more), and the K/V cache for it takes several GB of VRAM.
The K/V cache is `f16` by default, Ollama's default.

To use Claude Code with `qwen3-coder:30b` on a GPU with 24 GB of VRAM, setting `OLLAMA_KV_CACHE_TYPE=q8_0` in `.env` is recommended:

```console
$ echo "OLLAMA_KV_CACHE_TYPE=q8_0" >> .env
```

`qwen3-coder:30b` uses attention in all of its layers, so its K/V cache is large: with `f16`, only 48k tokens (`num_ctx` 49152) fit in the VRAM of an NVIDIA GeForce RTX 3090 along with the model.
`q8_0` roughly halves the cache, and so roughly doubles the context.
It applies to all models, and needs flash attention, which is left to its default (`auto` on supported GPUs).

## Model storage

Downloaded models are stored in the `ollama-models` volume, mounted on `/root/.ollama/models`.
The rest of `/root/.ollama` (the Ollama key pair and caches) stays in the `ollama` volume.

To store models in a host directory instead, set `OLLAMA_MODELS_PATH` in `.env`:

```console
$ echo "OLLAMA_MODELS_PATH=/srv/ollama-models" >> .env
```

Docker creates the directory owned by root if it does not exist.
A relative path must start with `./` (e.g. `./models`); otherwise it is taken as a volume name.

### Migrating models from the `ollama` volume

Models were stored in the `ollama` volume before.
After the change, the new mount hides them, so Ollama lists no models while they still take disk space.
Move them to the new location:

```console
$ docker compose down
$ docker compose up --no-start
$ docker run --rm -v ollama_ollama:/from -v ollama_ollama-models:/to alpine \
    sh -c 'cp -a /from/models/. /to/ && rm -rf /from/models/*'
$ docker compose up -d
$ docker compose exec ollama ollama list
```

`docker compose up --no-start` lets Compose create the new volume, so that it carries Compose's labels.
When `OLLAMA_MODELS_PATH` is set, replace `-v ollama_ollama-models:/to` with `-v "$OLLAMA_MODELS_PATH":/to`.
The copy temporarily needs as much free space as the models take.
The volume names are prefixed with the Compose project name (`ollama` by default).

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

## Claude Code with local models

`bin/claude-local` runs Claude Code with a model on this Ollama, with the web search above.
The command name chooses the model:

| Command | Model |
| --- | --- |
| `claude-local` | `gpt-oss:20b` |
| `claude-qwen` | `qwen3.6:27b-coding-cc-nvidia-rtx-3090` |
| `claude-gemma` | `gemma4:26b-cc-nvidia-rtx-3090` |

Install them by making symbolic links in a directory on `PATH`:

```console
$ ln -s "$PWD"/bin/claude-local "$PWD"/bin/claude-qwen "$PWD"/bin/claude-gemma ~/.local/bin/
```

They accept the options of `claude`, and these environment variables:

- `CLAUDE_LOCAL_MODEL`: the model to use instead, e.g. `CLAUDE_LOCAL_MODEL=qwen3.8:27b-cc-nvidia-rtx-3090 claude-qwen`
- `CLAUDE_LOCAL_OLLAMA_URL`: the URL of Ollama (default: `http://127.0.0.1:11434`)
- `MCP_SEARXNG_URL`: the URL of mcp-searxng (default: `http://127.0.0.1:3000`)

`claude-local` asks Ollama for `num_ctx` of the model, and passes it to Claude Code as `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, so that Claude Code compacts the conversation before it exceeds the context.

### Models for Claude Code

Claude Code sends no context length to Ollama, so Ollama uses `num_ctx` of the model, or `OLLAMA_CONTEXT_LENGTH` of the server.
`modelfiles/<name>/<tag>.Modelfile` defines a model `<name>:<tag>` that sets `num_ctx` on a downloaded model, without copying its weights.
The models with the `-cc-nvidia-rtx-3090` suffix have the largest `num_ctx` (up to 128k) that runs at `100% GPU` on an NVIDIA GeForce RTX 3090 (24 GB) with the `f16` K/V cache.

Download the models, and create the models from the Modelfiles:

```console
$ for model in qwen3-coder:30b qwen3.6:35b-a3b-coding qwen3.6:27b-coding qwen3.8:27b gemma4:26b; do
    docker compose exec ollama ollama pull "$model"
  done
$ for path in modelfiles/*/*.Modelfile; do
    model="$(basename "$(dirname "$path")"):$(basename "$path" .Modelfile)"
    docker compose exec -T ollama \
      sh -c 'cat > /tmp/Modelfile && ollama create "$1" -f /tmp/Modelfile' sh "$model" < "$path"
  done
```

Not every model calls tools of Claude Code reliably.
In a short test, `qwen3-coder:30b` often wrote a tool call as text instead of calling the tool, while `qwen3.6:27b-coding`, `qwen3.8:27b`, and `gemma4:26b` called them.

## References

- [ollama/ollama - Docker Image | Docker Hub](https://hub.docker.com/r/ollama/ollama)
- [Ollama library](https://ollama.com/library)
- [searxng/searxng - Docker Image | Docker Hub](https://hub.docker.com/r/searxng/searxng)
- [isokoliuk/mcp-searxng - Docker Image | Docker Hub](https://hub.docker.com/r/isokoliuk/mcp-searxng)
