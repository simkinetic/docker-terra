# terra-docker

This repository contains Dockerfiles for building Docker images that include Terra (a low-level counterpart to Lua) and cosm (a command-line package management tool), set up in a sandbox environment with git and ca-certificates. Separate files for arm64 (e.g., Mac Apple Silicon) and amd64 (e.g., Linux clusters) architectures.

The Dockerfiles build LLVM and Terra from source, download pre-built cosm binaries, and configure a bash sandbox with a custom prompt.

## Prerequisites
- Docker with Buildx support.

## Local Building

### arm64 (native on Mac ARM64)
```
docker buildx build -t terra-arm64 --platform linux/arm64 -f Dockerfile.arm64 .
```

### amd64 (emulated on Mac, native on x86_64)
```
docker buildx build -t terra-amd64 --platform linux/amd64 -f Dockerfile.amd64 .
```

**Notes**:
- amd64 builds on arm64 use QEMU (slower).
- Verify: `docker run --rm terra-arm64 terra --version` and `docker run --rm -e COSM_DEPOT_PATH=/root/.cosm terra-arm64 cosm --version`.

## Running Locally
```
docker run -it --rm terra-arm64  # Or terra-amd64
```
- Mount files: `docker run -it --rm -v $(pwd):/workdir -w /workdir terra-arm64`
- Direct: `docker run --rm terra-arm64 terra --version`

## CI/CD with GitHub Actions
The workflow in `.github/workflows/publish.yml` builds, tests, and pushes to GHCR (`ghcr.io/simkinetic/terra-arm64` and `ghcr.io/simkinetic/terra-amd64`). Triggers on tagged pushes (`v*`).

### Setup
1. Repo under https://github.com/simkinetic/ (e.g., simkinetic/terra-docker).
2. Workflow uses `${{ secrets.GITHUB_TOKEN }}`.
3. Make packages public: Org packages → terra-arm64/terra-amd64 → Settings → Public.

### Trigger
```
git tag v0.1.0
git push origin tag v0.1.0
```
- Monitor in Actions tab: Builds/tests arm64/amd64, pushes if pass.

### Pulling from GHCR
```
docker pull ghcr.io/simkinetic/terra-arm64:latest  # Or terra-amd64:latest, or :v1.0
docker run -it --rm ghcr.io/simkinetic/terra-arm64:latest
```