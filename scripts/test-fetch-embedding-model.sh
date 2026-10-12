#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
model=fast-bge-small-zh-v1.5
source=ongrid-v0.17.6-linux-arm64
mkdir -p "$work/bin" "$work/payload/$source/embeddings/$model"
for file in model_optimized.onnx tokenizer_config.json special_tokens_map.json config.json tokenizer.json vocab.txt ort_config.json; do
    printf '%s\n' "$file" > "$work/payload/$source/embeddings/$model/$file"
done
tar -cJf "$work/model.tar.xz" -C "$work/payload" "$source"
cat > "$work/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
while (( $# )); do
    case "$1" in
        -o) output=$2; shift 2 ;;
        --retry|--connect-timeout) shift 2 ;;
        -fL) shift ;;
        *) url=$1; shift ;;
    esac
done
[[ "$url" == 'https://github.com/ongridio/ongrid/releases/download/v0.17.6/ongrid-v0.17.6-linux-arm64.tar.xz' ]]
[[ "${MOCK_DOWNLOAD_FAIL:-0}" != 1 ]] || exit 22
cp "$MOCK_ARCHIVE" "$output"
SH
cat > "$work/bin/sha256sum" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == '-c -' ]]
read -r expected archive
[[ "$expected" == 4f3b55dc8215d6bb45f8c4a236fcd7d907e635a6bdabc1ab71b84cd5e3a6b6e0 && -s "$archive" ]]
[[ "${MOCK_CHECKSUM_FAIL:-0}" != 1 ]]
SH
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH" MOCK_ARCHIVE="$work/model.tar.xz"
fetch() { bash "$repo_root/dist/fetch-embedding-model.sh" "$work/cache" > "$work/fetch.log" 2>&1; }
fetch
cmp "$work/payload/$source/embeddings/$model/model_optimized.onnx" "$work/cache/$model/model_optimized.onnx"
MOCK_DOWNLOAD_FAIL=1 fetch # A complete cache does not require the network.

rm "$work/cache/$model/vocab.txt"
printf 'previous model\n' > "$work/cache/$model/model_optimized.onnx"
for failure in checksum download missing; do
    export MOCK_CHECKSUM_FAIL=0 MOCK_DOWNLOAD_FAIL=0
    case "$failure" in
        checksum) export MOCK_CHECKSUM_FAIL=1 ;;
        download) export MOCK_DOWNLOAD_FAIL=1 ;;
        missing)
            rm "$work/payload/$source/embeddings/$model/vocab.txt"
            tar -cJf "$MOCK_ARCHIVE" -C "$work/payload" "$source"
            ;;
    esac
    if fetch; then
        echo "fetch-embedding-model accepted $failure" >&2; exit 1
    fi
    [[ "$(cat "$work/cache/$model/model_optimized.onnx")" == 'previous model' ]]
done
echo 'embedding model fetch tests passed'
