# terra-docker

```
docker buildx build --platform linux/amd64 -t terra-amd64 .
docker tag terra-amd64:latest ghcr.io/simkinetic/terra-amd64:latest
docker push ghcr.io/simkinetic/terra-amd64:latest
```

to turn it into apptainer do:
```
apptainer build --sandbox terra-amd64_sandbox docker://ghcr.io/simkinetic/terra-amd64:latest
apptainer run --writable terra-amd64_sandbox
```


to run using ssh keys:
```
docker run -it --rm -v $(pwd):/workdir -v $HOME/.ssh:/root/.ssh:ro -w /workdir terra-arm64
```