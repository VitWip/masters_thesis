#!/usr/bin/env bash
# =============================================================================
# Download qwen_3_8b_fp8mixed.safetensors into ComfyUI text_encoders folder
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Config ────────────────────────────────────────────────────────────────────
DEST_DIR="${HOME}/ComfyUI/models/text_encoders"
FILE_NAME="qwen_3_8b_fp8mixed.safetensors"
URLS=(
  "https://huggingface.co/kp-forks/FLUX.2-klein-9B/resolve/main/split_files/text_encoders/${FILE_NAME}"
  "https://huggingface.co/kp-forks/FLUX.2-klein-9B/resolve/main/${FILE_NAME}"
  "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/${FILE_NAME}"
  "https://huggingface.co/Comfy-Org/vae-text-encoder-for-flux-klein-9b/resolve/main/split_files/text_encoders/${FILE_NAME}"
)

# ── If file already exists in /work, just move it ────────────────────────────
if [[ -f "/work/${FILE_NAME}" ]]; then
  info "Found ${FILE_NAME} in /work — moving it to ${DEST_DIR} ..."
  mkdir -p "$DEST_DIR"
  mv "/work/${FILE_NAME}" "${DEST_DIR}/${FILE_NAME}"
  info "Done! File moved to ${DEST_DIR}/${FILE_NAME}"
  exit 0
fi

# ── Otherwise download from Hugging Face ─────────────────────────────────────
info "Creating destination folder: $DEST_DIR"
mkdir -p "$DEST_DIR"

DEST_FILE="${DEST_DIR}/${FILE_NAME}"

if [[ -f "$DEST_FILE" ]]; then
  info "File already exists at ${DEST_FILE} — skipping download."
  exit 0
fi

info "Downloading ${FILE_NAME} from Hugging Face..."
info "This file is ~8GB, please be patient."

TMP_FILE="${DEST_FILE}.tmp"
rm -f "$TMP_FILE"

for URL in "${URLS[@]}"; do
  info "Trying: $URL"
  if command -v wget >/dev/null 2>&1; then
    if wget --progress=bar:force -O "$TMP_FILE" "$URL"; then
      mv "$TMP_FILE" "$DEST_FILE"
      break
    fi
  elif command -v curl >/dev/null 2>&1; then
    if curl -L --progress-bar -o "$TMP_FILE" "$URL"; then
      mv "$TMP_FILE" "$DEST_FILE"
      break
    fi
  else
    error "Neither wget nor curl is installed. Please install one and retry."
  fi
  rm -f "$TMP_FILE"
done

# ── Verify ────────────────────────────────────────────────────────────────────
if [[ -f "$DEST_FILE" ]]; then
  SIZE=$(du -sh "$DEST_FILE" | cut -f1)
  info "Download complete! File size: ${SIZE}"
  info "Saved to: ${DEST_FILE}"
else
  error "Download failed. Please check your internet connection and try again."
fi

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  All done! Restart ComfyUI to use the new text encoder.${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Restart command:"
echo "    cd ~/ComfyUI && ./start.sh"
echo ""
