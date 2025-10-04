# syntax=docker/dockerfile:1
FROM rockylinux:8 AS builder

# Install dependencies
RUN dnf -y groupinstall "Development Tools" && \
    dnf -y install git curl cmake pkgconfig gcc-c++ make python3 openssl-devel

# Install Rust (latest stable)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Clone latest stable Helix (25.07.1 tag)
WORKDIR /src
RUN git clone --depth=1 --branch 25.07.1 https://github.com/helix-editor/helix.git
WORKDIR /src/helix

# Pull grammar submodules
RUN git submodule update --init --recursive

# Build release binary
RUN cargo build --release --locked

# Final image: minimal runtime with hx
FROM rockylinux:8 AS runtime

# Copy hx binary and runtime files
COPY --from=builder /src/helix/target/release/hx /usr/local/bin/hx
COPY --from=builder /src/helix/runtime /usr/local/share/helix/runtime

# Add helix runtime path
ENV HELIX_RUNTIME=/usr/local/share/helix/runtime

# Default command: run hx
ENTRYPOINT ["hx"]

