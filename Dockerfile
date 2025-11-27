# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04 AS builder
ARG TARGETPLATFORM
ENV PLATFORM=${TARGETPLATFORM}
CMD echo "Building Terra Language sandbox for the ${PLATFORM} platform."

# Install build deps (Ubuntu has great static support)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang lld cmake ninja-build git python3 \
    libstdc++-13-dev wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------
# Define compiler environment variables (ADDED)
# ------------------------------------------------------------------
ENV CC=/usr/bin/clang
ENV CXX=/usr/bin/clang++
ENV CXXFLAGS="-std=c++11 -march=native"
ENV CFLAGS="-march=native"

# ------------------------------------------------------------------
# 1. Build minimal static LLVM 18 + Clang (only what Terra needs)
# ------------------------------------------------------------------
ENV LLVM_VERSION=18.1.8

RUN wget -q https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/llvm-project-${LLVM_VERSION}.src.tar.xz && \
    tar xf llvm-project-${LLVM_VERSION}.src.tar.xz && \
    rm llvm-project-${LLVM_VERSION}.src.tar.xz

RUN mkdir /llvm-build && \
    cd /llvm-build && \
    cmake -G Ninja ../llvm-project-${LLVM_VERSION}.src/llvm \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/llvm-install \
      -DCMAKE_C_FLAGS="${CFLAGS}" \
      -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
      -DLLVM_ENABLE_PROJECTS="clang" \
      -DLLVM_TARGETS_TO_BUILD="X86;AArch64" \
      -DLLVM_ENABLE_TERMINFO=OFF \
      -DLLVM_ENABLE_LIBEDIT=OFF \
      -DLLVM_ENABLE_ZLIB=OFF \
      -DLLVM_ENABLE_LIBXML2=OFF \
      -DLLVM_ENABLE_ASSERTIONS=OFF \
      -DLLVM_BUILD_LLVM_DYLIB=OFF \
      -DLLVM_LINK_LLVM_DYLIB=OFF \
      -DBUILD_SHARED_LIBS=OFF && \
    ninja install && \
    rm -rf /llvm-build /llvm-project-${LLVM_VERSION}.src

# ------------------------------------------------------------------
# 2. Build Terra (renehiemstra fork, raii-v3-refac branch)
# ------------------------------------------------------------------
RUN git clone https://github.com/renehiemstra/terra.git /terra && \
    cd /terra && \
    git checkout raii-v3-refac && \
    mkdir -p build && \
    cd build && \
    cmake .. \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/terra-install \
      -DCMAKE_PREFIX_PATH=/llvm-install \
      -DCMAKE_C_FLAGS="${CFLAGS}" \
      -DCMAKE_CXX_FLAGS="${CXXFLAGS}"  && \
    ninja install/strip

# ------------------------------------------------------------------
# 2.5. Download and verify cosm v0.3.1 pre-built binary
# ------------------------------------------------------------------
RUN if [ "${PLATFORM}" = "linux/arm64" ]; then \
      FILE="cosm-linux-arm64.tar.gz"; \
      HASH="c221b86d95c951268fbc7487d37900ce5b853e460d3a3c7312b335b2c41b9f83"; \
      BINARY="cosm-linux-arm64"; \
      echo "Downloading and installing: ${FILE} (binary: ${BINARY})"; \
    else \
      FILE="cosm-linux-amd64.tar.gz"; \
      HASH="e16c5187f3ad0de2f9e1c238782c37bd02eb6aee65d07b19514250b3e887ab63"; \
      BINARY="cosm-linux-amd64"; \
      echo "Downloading and installing: ${FILE} (binary: ${BINARY})"; \
    fi && \
    wget -q https://github.com/renehiemstra/cosm/releases/download/v0.3.1/${FILE} && \
    echo "${HASH}  ${FILE}" > check.sha && \
    sha256sum -c check.sha && \
    tar xzf ${FILE} && \
    mv ${BINARY} /terra-install/bin/cosm && \
    rm ${FILE} check.sha

# ------------------------------------------------------------------
# 3. Final small image (exact glibc match)
# ------------------------------------------------------------------
FROM ubuntu:24.04

# Install git, ca-certificates, openssh-client, libc6-dev, and clang for the sandbox
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates openssh-client libc6-dev clang && \
    rm -rf /var/lib/apt/lists/*

# Set up symlinks for clang and clang++
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-18 180 \
    --slave /usr/bin/clang++ clang++ /usr/bin/clang++-18

# Copy the full Terra install (bin, lib, share) for module access
COPY --from=builder /terra-install/ /usr/local/

# Set the cosm depot path and clone the terra standard registry
ENV COSM_DEPOT_PATH="/root/.cosm"
RUN cosm registry clone https://github.com/simkinetic/TerraStandard.git

# Add pretty terminal prompt and export compiler
RUN echo 'PS1="\[\e[32m\]terra-sandbox\[\e[m\] \[\e[34m\]\w\[\e[m\]\$ "' >> /root/.bashrc && \
    echo 'export CC=/usr/bin/clang' >> /root/.bashrc && \
    echo 'export CXX=/usr/bin/clang++' >> /root/.bashrc && \
    echo 'export CFLAGS="-O2 -march=native -fPIC -g"' >> /root/.bashrc && \
    echo 'export CXXFLAGS="-O2 -std=c++11 -march=native -fPIC -g"' >> /root/.bashrc

# Default to interactive bash shell for sandbox
CMD ["/bin/bash"]