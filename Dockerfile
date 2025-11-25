# syntax=docker/dockerfile:1.7
ARG TARGET_PLATFORM=linux/arm64
FROM --platform=$TARGET_PLATFORM ubuntu:24.04 AS builder

# Install build deps (Ubuntu has great static support)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang lld cmake ninja-build git python3 \
    libstdc++-13-dev wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

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
      -DLLVM_ENABLE_PROJECTS="clang" \
      -DLLVM_TARGETS_TO_BUILD="X86;AArch64" \
      -DLLVM_ENABLE_TERMINFO=OFF \
      -DLLVM_ENABLE_LIBEDIT=OFF \
      -DLLVM_ENABLE_ZLIB=OFF \
      -DLLVM_ENABLE_LIBXML2=OFF \
      -DLLVM_ENABLE_ASSERTIONS=OFF \
      -DLLVM_BUILD_LLVM_DYLIB=OFF \
      -DLLVM_LINK_LLVM_DYLIB=OFF \
      -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ && \
    ninja install && \
    rm -rf /llvm-build /llvm-project-${LLVM_VERSION}.src

# ------------------------------------------------------------------
# 2. Build Terra (renehiemstra fork) — static for libgcc/libstdc++, dynamic for libc
# ------------------------------------------------------------------
RUN git clone https://github.com/renehiemstra/terra.git /terra && \
    mkdir -p /terra/build && \
    cd /terra/build && \
    cmake .. \
      -G Ninja \
      -DCMAKE_INSTALL_PREFIX=/terra-install \
      -DCMAKE_PREFIX_PATH=/llvm-install \
      -DCMAKE_C_COMPILER=/llvm-install/bin/clang \
      -DCMAKE_CXX_COMPILER=/llvm-install/bin/clang++ \
      -DBUILD_SHARED_LIBS=OFF \
      -DTERRA_STATIC_LINK_LLVM=ON \
      -DTERRA_SLIB_INCLUDE_LLVM=ON \
      -DTERRA_STATIC_LINK_LUAJIT=ON \
      -DTERRA_SLIB_INCLUDE_LUAJIT=ON \
      -DCMAKE_EXE_LINKER_FLAGS="-static-libgcc -static-libstdc++ -pthread" \
      -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc -static-libstdc++ -pthread" && \
    ninja install/strip

# ------------------------------------------------------------------
# 2.5. Download and verify cosm v0.3.1 pre-built binary
# ------------------------------------------------------------------
RUN wget -q https://github.com/renehiemstra/cosm/releases/download/v0.3.1/cosm-linux-arm64.tar.gz && \
    echo "c221b86d95c951268fbc7487d37900ce5b853e460d3a3c7312b335b2c41b9f83  cosm-linux-arm64.tar.gz" > check.sha && \
    sha256sum -c check.sha && \
    tar xzf cosm-linux-arm64.tar.gz && \
    mv cosm-linux-arm64 /terra-install/bin/cosm && \
    rm cosm-linux-arm64.tar.gz check.sha

# ------------------------------------------------------------------
# 3. Final small image (exact glibc match)
# ------------------------------------------------------------------
FROM --platform=$TARGET_PLATFORM ubuntu:24.04

# Install git and ca-certificates for the sandbox
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Copy binaries to /usr/local/bin for PATH access
COPY --from=builder /terra-install/bin/terra /usr/local/bin/terra
COPY --from=builder /terra-install/bin/cosm /usr/local/bin/cosm

# Customize bash prompt for better appearance
RUN echo 'PS1="\[\e[32m\]terra-sandbox\[\e[m\] \[\e[34m\]\w\[\e[m\]\$ "' >> /root/.bashrc

# Default to interactive bash shell for sandbox
CMD ["/bin/bash"]