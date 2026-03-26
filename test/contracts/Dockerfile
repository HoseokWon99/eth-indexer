FROM ghcr.io/foundry-rs/foundry:latest

WORKDIR /workspace

# Copy dependency manifests and install libs
COPY foundry.toml foundry.lock ./
COPY lib/ ./lib/

# Copy source and scripts
COPY src/ ./src/
COPY script/ ./script/

# Pre-build contracts
RUN forge build

ENTRYPOINT []
CMD ["sh", "-c", \
  "forge script script/Deploy.s.sol:Deploy \
    --rpc-url $RPC_URL \
    --broadcast \
    --legacy \
    -vv && \
  forge script script/GenerateEvents.s.sol:GenerateEvents \
    --rpc-url $RPC_URL \
    --broadcast \
    --legacy \
    -vv"]