#!/usr/bin/env bash
# fetch-embedding-model.sh — pre-cache the BGE-small-zh-v1.5 ONNX model
# into .cache/embedding-models/ so dist/package.sh can bundle it into
# the install tarball. Run once on a host with GitHub reach;
# subsequent `make package` runs pick up the cache.
#
# Why a separate script: the model is ~55MB download + ~97MB on disk
# after extraction, slow over CN networks; pinning a build step on
# network is brittle. dist/package.sh warns + skips if not pre-cached.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
DEST=${1:-"$REPO_ROOT/.cache/embedding-models"}
mkdir -p "$DEST"

log()  { printf '[fetch-emb] %s\n' "$*"; }
die()  { printf '[fetch-emb] error: %s\n' "$*" >&2; exit 1; }

# The upstream GCS object is no longer public. This release contains the
# same model bytes in the cache layout expected by fastembed-go v1.0.0.
MODEL=fast-bge-small-zh-v1.5
SOURCE=ongrid-v0.17.6-linux-arm64
SOURCE_SHA256=4f3b55dc8215d6bb45f8c4a236fcd7d907e635a6bdabc1ab71b84cd5e3a6b6e0
TARGET="$DEST/$MODEL"

FILES=(model_optimized.onnx tokenizer_config.json special_tokens_map.json
       config.json tokenizer.json vocab.txt ort_config.json)

mkdir -p "$TARGET"
missing=0
for f in "${FILES[@]}"; do
    if [[ ! -s "$TARGET/$f" ]]; then
        missing=1
        break
    fi
done

if [[ "$missing" -eq 0 ]]; then
    log "$MODEL already present — skipping"
else
    tmp=$(mktemp -d "$DEST/.fetch-model.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    url="https://github.com/ongridio/ongrid/releases/download/v0.17.6/${SOURCE}.tar.xz"
    log "fetching $url"
    curl -fL --retry 3 --connect-timeout 15 -o "$tmp/model.tar.xz" "$url" || die "failed to fetch $url"
    printf '%s  %s\n' "$SOURCE_SHA256" "$tmp/model.tar.xz" | sha256sum -c - \
        || die "model archive checksum mismatch"
    tar -xJf "$tmp/model.tar.xz" -C "$tmp" "$SOURCE/embeddings/$MODEL"
    for f in "${FILES[@]}"; do
        [[ -s "$tmp/$SOURCE/embeddings/$MODEL/$f" ]] || die "downloaded model missing $f"
    done
    rm -rf "$TARGET"
    mv "$tmp/$SOURCE/embeddings/$MODEL" "$TARGET"
fi

log "cached $TARGET ($(du -sh "$TARGET" | awk '{print $1}'))"
log "next \`make package\` will bundle this under embeddings/$MODEL/"
