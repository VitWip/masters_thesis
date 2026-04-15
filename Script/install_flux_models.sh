#!/usr/bin/env bash
# =============================================================================
# Download Flux Klein 9B models into ComfyUI folders
# Models: FluxKlein9b, FluxKlein9b FP8, Flux2 VAE, qwen_3_8b_fp8mixed, sam3.pt,
#         Florence-2-base-ft, Florence-2-large-ft, face_yolov8m.pt
# LoRAs:  DarkKlein9b_v2BFS_extracted_lora_r256, add_real_details
# =============================================================================
set -eo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# =============================================================================
# Config
# =============================================================================
COMFY_DIR="${HOME}/ComfyUI"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIFFUSION_DIR="${COMFY_DIR}/models/diffusion_models"
CHECKPOINT_DIR="${COMFY_DIR}/models/checkpoints"
VAE_DIR="${COMFY_DIR}/models/vae"
TEXT_ENC_DIR="${COMFY_DIR}/models/text_encoders"
SAM3_DIR="${COMFY_DIR}/models/sam3"
ULTRALYTICS_DIR="${COMFY_DIR}/models/ultralytics"
LLM_DIR="${COMFY_DIR}/models/LLM"
LORA_DIR="${COMFY_DIR}/models/loras"

[[ -d "$COMFY_DIR" ]] || error "ComfyUI not found at $COMFY_DIR."

# =============================================================================
# CivitAI Token
# Required for:
#   - ultimate_upscaler_klein9b (CivitAI model)
# Steps:
#   1. Create account / log in: https://civitai.com
#   2. Get API key:             https://civitai.com/user/account  (API Keys section)
# =============================================================================
if [[ -z "${CIVITAI_TOKEN:-}" ]]; then
  echo ""
  warn "CIVITAI_TOKEN is not set."
  warn "DarkKlein9b_v2BFS_extracted_lora_r256 requires a CivitAI API key."
  warn "Get your key at: https://civitai.com/user/account"
  echo ""
  read -rp "Paste your CivitAI API key (or press Enter to skip): " CIVITAI_TOKEN
fi

# =============================================================================
# HuggingFace Token
# Required for:
#   - FluxKlein9b FP8 (black-forest-labs gated model)
#   - sam3.pt         (facebook gated model)
# Steps:
#   1. Accept FluxKlein9b FP8 license: https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8
#   2. Accept SAM3 license:            https://huggingface.co/facebook/sam3
#   3. Get your token:                 https://huggingface.co/settings/tokens
# =============================================================================
if [[ -z "${HF_TOKEN:-}" ]]; then
  echo ""
  warn "HF_TOKEN is not set."
  warn "FluxKlein9b FP8 and sam3.pt require a HuggingFace token."
  warn "1. Accept FluxKlein9b FP8 license: https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8"
  warn "2. Accept SAM3 license:            https://huggingface.co/facebook/sam3"
  warn "3. Get token at:                   https://huggingface.co/settings/tokens"
  echo ""
  read -rp "Paste your HuggingFace token (or press Enter to skip gated models): " HF_TOKEN
fi

# =============================================================================
# Download helper
# =============================================================================
download_file() {
  local name="$1"
  local url="$2"
  local dest="$3"
  local token="${4:-}"

  if [[ -f "$dest" ]]; then
    warn "[${name}] Already exists — skipping."
    return
  fi

  info "[${name}] Downloading..."
  local tmp="${dest}.tmp"
  rm -f "$tmp"

  local auth_header=""
  [[ -n "$token" ]] && auth_header="Authorization: Bearer ${token}"

  if command -v wget >/dev/null 2>&1; then
    if [[ -n "$auth_header" ]]; then
      wget --header="$auth_header" --progress=bar:force -O "$tmp" "$url" || { rm -f "$tmp"; return 1; }
    else
      wget --progress=bar:force -O "$tmp" "$url" || { rm -f "$tmp"; return 1; }
    fi
  elif command -v curl >/dev/null 2>&1; then
    if [[ -n "$auth_header" ]]; then
      curl -L --progress-bar -H "$auth_header" -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
    else
      curl -L --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
    fi
  else
    error "Neither wget nor curl found."
  fi

  mv "$tmp" "$dest"
  SIZE=$(du -sh "$dest" | cut -f1)
  info "[${name}] Done! Size: ${SIZE}"
}

ensure_file_alias() {
  local source="$1"
  local dest="$2"

  [[ -f "$source" ]] || return
  [[ -f "$dest" ]] && return

  mkdir -p "$(dirname "$dest")"
  if ln "$source" "$dest" 2>/dev/null; then
    info "Created hard link: ${dest}"
  else
    cp -p "$source" "$dest"
    info "Copied file to: ${dest}"
  fi
}

download_hf_snapshot() {
  local repo_id="$1"
  local dest_dir="$2"

  if [[ -f "${dest_dir}/config.json" && ( -f "${dest_dir}/model.safetensors" || -f "${dest_dir}/pytorch_model.bin" ) ]]; then
    warn "[${repo_id}] Already exists — skipping snapshot download."
    return
  fi

  mkdir -p "$dest_dir"
  info "[${repo_id}] Downloading Hugging Face snapshot to ${dest_dir}..."

  python - "$repo_id" "$dest_dir" <<'PY'
import os
import sys

repo_id, dest_dir = sys.argv[1], sys.argv[2]

try:
    from huggingface_hub import snapshot_download
except ImportError as exc:
    raise SystemExit(f"huggingface_hub is required to download {repo_id}: {exc}")

snapshot_download(
    repo_id=repo_id,
    local_dir=dest_dir,
    local_dir_use_symlinks=False,
)
PY
}

# =============================================================================
# Create directories
# =============================================================================
info "Creating model directories..."
mkdir -p "$DIFFUSION_DIR" "$CHECKPOINT_DIR" "$VAE_DIR" "$TEXT_ENC_DIR" "$SAM3_DIR" "$ULTRALYTICS_DIR" "$LLM_DIR" "$LORA_DIR"

# =============================================================================
# 1. FluxKlein9b — diffusion_models + checkpoints (FREE)
# =============================================================================
FLUX_DIR="${DIFFUSION_DIR}/flux"
FLUX_UNET_DEST="${FLUX_DIR}/flux-2-klein-9b.safetensors"
FLUX_LEGACY_DEST="${DIFFUSION_DIR}/FluxKlein9b.safetensors"
FLUX_CHECKPOINT_DEST="${CHECKPOINT_DIR}/flux-2-klein-9b.safetensors"

mkdir -p "$FLUX_DIR"

if [[ -f "$FLUX_LEGACY_DEST" && ! -f "$FLUX_UNET_DEST" ]]; then
  info "[FluxKlein9b] Migrating legacy filename to ${FLUX_UNET_DEST}..."
  mv "$FLUX_LEGACY_DEST" "$FLUX_UNET_DEST"
elif [[ -f "$FLUX_CHECKPOINT_DEST" && ! -f "$FLUX_UNET_DEST" ]]; then
  info "[FluxKlein9b] Reusing checkpoint copy for diffusion_models..."
  ensure_file_alias "$FLUX_CHECKPOINT_DEST" "$FLUX_UNET_DEST"
fi

info "[FluxKlein9b] Downloading full checkpoint from kp-forks/FLUX.2-klein-9B (this is ~18GB)..."
download_file \
  "flux-2-klein-9b.safetensors" \
  "https://huggingface.co/kp-forks/FLUX.2-klein-9B/resolve/main/flux-2-klein-9b.safetensors" \
  "$FLUX_UNET_DEST"

ensure_file_alias "$FLUX_UNET_DEST" "$FLUX_LEGACY_DEST"
ensure_file_alias "$FLUX_UNET_DEST" "$FLUX_CHECKPOINT_DEST"

if [[ -n "${HF_TOKEN:-}" ]]; then
  info "[FluxKlein9b FP8] Downloading quantized checkpoint from black-forest-labs/FLUX.2-klein-9b-fp8..."
  download_file \
    "FluxKlein9b_fp8.safetensors" \
    "https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8/resolve/main/flux-2-klein-9b-fp8.safetensors" \
    "${DIFFUSION_DIR}/FluxKlein9b_fp8.safetensors" \
    "$HF_TOKEN"
else
  warn "[FluxKlein9b FP8] Skipped — no HF_TOKEN provided."
fi

# =============================================================================
# 2. Flux2 VAE — vae (FREE)
# =============================================================================
download_file \
  "flux2-vae.safetensors" \
  "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/vae/flux2-vae.safetensors" \
  "${VAE_DIR}/flux2-vae.safetensors"

# =============================================================================
# 3. qwen_3_8b_fp8mixed — text_encoders (FREE)
#    Checks /work first, then downloads
# =============================================================================
QWEN_DEST="${TEXT_ENC_DIR}/qwen_3_8b_fp8mixed.safetensors"
QWEN_WORK="/work/qwen_3_8b_fp8mixed.safetensors"

if [[ -f "$QWEN_DEST" ]]; then
  warn "[qwen_3_8b_fp8mixed] Already exists — skipping."
elif [[ -f "$QWEN_WORK" ]]; then
  info "[qwen_3_8b_fp8mixed] Found in /work — moving to text_encoders..."
  mv "$QWEN_WORK" "$QWEN_DEST"
  info "[qwen_3_8b_fp8mixed] Done!"
else
  download_file \
    "qwen_3_8b_fp8mixed.safetensors" \
    "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
    "$QWEN_DEST"
fi

# =============================================================================
# 4. sam3.pt — sam3 folder (GATED, needs HF token + facebook/sam3 access)
#    Required by: easy sam3ModelLoader, easy sam3ImageSegmentation
# =============================================================================
SAM3_DEST="${SAM3_DIR}/sam3.pt"

if [[ -f "$SAM3_DEST" ]]; then
  warn "[sam3.pt] Already exists — skipping."
elif [[ -n "${HF_TOKEN:-}" ]]; then
  info "[sam3.pt] Downloading from facebook/sam3 (this is ~900MB)..."
  download_file \
    "sam3.pt" \
    "https://huggingface.co/facebook/sam3/resolve/main/sam3.pt" \
    "$SAM3_DEST" \
    "$HF_TOKEN"
else
  warn "[sam3.pt] Skipped — no HF_TOKEN provided."
  warn "[sam3.pt] To download it:"
  warn "  1. Accept access at: https://huggingface.co/facebook/sam3"
  warn "  2. Re-run with:      export HF_TOKEN=hf_xxxx && bash install_flux_models.sh"
fi

# =============================================================================
# 5. LoRAs
# =============================================================================

# 5a. ultimate_upscaler_klein9b — CivitAI (requires API key)
if [[ -n "${CIVITAI_TOKEN:-}" ]]; then
  download_file \
    "ultimate_upscaler_klein9b.safetensors" \
    "https://civitai.com/api/download/models/2781657?token=${CIVITAI_TOKEN}" \
    "${LORA_DIR}/ultimate_upscaler_klein9b.safetensors"
else
  warn "[ultimate_upscaler_klein9b] Skipped — no CIVITAI_TOKEN provided."
  warn "[ultimate_upscaler_klein9b] To download it:"
  warn "  1. Get API key at: https://civitai.com/user/account"
  warn "  2. Re-run with:    export CIVITAI_TOKEN=your_key && bash install_flux_models.sh"
fi

# 5b. add_real_details — HuggingFace (FREE)
download_file \
  "add_real_details.safetensors" \
  "https://huggingface.co/OedoSoldier/detail-tweaker-lora/resolve/main/add_detail.safetensors" \
  "${LORA_DIR}/add_real_details.safetensors"

# 5c. Local project LoRA — keep source file in script folder, install copy/link in ComfyUI
LOCAL_TESTC_LORA_SRC="${SCRIPT_DIR}/TestCModelClothing_epoch_10.safetensors"
LOCAL_TESTC_LORA_DEST="${LORA_DIR}/TestCModelClothing_epoch_10.safetensors"

if [[ -f "$LOCAL_TESTC_LORA_SRC" ]]; then
  info "[TestCModelClothing_epoch_10] Installing local LoRA into ComfyUI..."
  ensure_file_alias "$LOCAL_TESTC_LORA_SRC" "$LOCAL_TESTC_LORA_DEST"
else
  warn "[TestCModelClothing_epoch_10] Local file not found at ${LOCAL_TESTC_LORA_SRC} — skipping."
fi

# =============================================================================
# 6. YOLO face detector — ultralytics (FREE)
#    Required by RMBG AILab_YoloV8 workflows using bbox/face_yolov8m.pt
# =============================================================================
download_file \
  "bbox/face_yolov8m.pt" \
  "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8m.pt" \
  "${ULTRALYTICS_DIR}/bbox/face_yolov8m.pt"

# =============================================================================
# 7. Florence-2 models — LLM (FREE)
#    Required by ComfyUI-Florence2 Florence2ModelLoader workflows
# =============================================================================
download_hf_snapshot \
  "microsoft/Florence-2-base-ft" \
  "${LLM_DIR}/Florence-2-base-ft"

download_hf_snapshot \
  "microsoft/Florence-2-large-ft" \
  "${LLM_DIR}/Florence-2-large-ft"

# =============================================================================
# Done!
# =============================================================================
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Download complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  diffusion_models → ${FLUX_UNET_DEST}"
echo "  diffusion_models → ${FLUX_LEGACY_DEST}"
echo "  checkpoints      → ${FLUX_CHECKPOINT_DEST}"
echo "  diffusion_models → ${DIFFUSION_DIR}/FluxKlein9b_fp8.safetensors"
echo "  vae              → ${VAE_DIR}/flux2-vae.safetensors"
echo "  text_encoders    → ${TEXT_ENC_DIR}/qwen_3_8b_fp8mixed.safetensors"
echo "  sam3             → ${SAM3_DIR}/sam3.pt"
echo "  loras            → ${LORA_DIR}/ultimate_upscaler_klein9b.safetensors"
echo "  loras            → ${LORA_DIR}/add_real_details.safetensors"
echo "  loras            → ${LORA_DIR}/TestCModelClothing_epoch_10.safetensors"
echo "  ultralytics      → ${ULTRALYTICS_DIR}/bbox/face_yolov8m.pt"
echo "  LLM              → ${LLM_DIR}/Florence-2-base-ft"
echo "  LLM              → ${LLM_DIR}/Florence-2-large-ft"
echo ""
echo "  ⚠  Make sure your VAELoader in ComfyUI points to:"
echo "     flux2-vae.safetensors  (no spaces)"
echo ""
echo "  Restart ComfyUI:"
echo "    cd ~/ComfyUI && ./start.sh"
echo ""
