# Ollama playground

play Ollama

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

## References

- [ollama/ollama - Docker Image | Docker Hub](https://hub.docker.com/r/ollama/ollama)
- [Ollama library](https://ollama.com/library)
