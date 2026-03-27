FROM ghcr.io/foundry-rs/foundry:latest

ENV ANVIL_HOST=0.0.0.0
ENV ANVIL_PORT=8545
ENV ANVIL_BLOCK_TIME=1
ENV ANVIL_MNEMONIC="test test test test test test test test test test test junk"

EXPOSE 8545

ENTRYPOINT ["/bin/sh", "-c", "anvil --host $ANVIL_HOST --port $ANVIL_PORT --block-time $ANVIL_BLOCK_TIME --mnemonic \"$ANVIL_MNEMONIC"]
