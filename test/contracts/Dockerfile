FROM ghcr.io/foundry-rs/foundry:latest

WORKDIR /workspace

# Copy dependency manifests and install libs
COPY foundry.toml foundry.lock ./
COPY lib/ ./lib/
COPY node_modules/ ./node_modules/

# Copy source and scripts
COPY src/ ./src/
COPY script/ ./script/

# Pre-build contracts
RUN forge build

ENTRYPOINT ["sh", "-c"]