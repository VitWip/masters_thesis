#!/usr/bin/env bash
# =============================================================================
# ComfyUI Custom Nodes Installer
# Installs all required custom node packages
# =============================================================================
set -eo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# =============================================================================
# Config
# =============================================================================
COMFY_DIR="${HOME}/ComfyUI"
CUSTOM_NODES_DIR="${COMFY_DIR}/custom_nodes"
VENV_DIR="${COMFY_DIR}/.venv"
ACTIVATE_SH="${VENV_DIR}/bin/activate"

# =============================================================================
# Checks
# =============================================================================
[[ -d "$COMFY_DIR" ]] || error "ComfyUI not found at $COMFY_DIR. Please install it first."
[[ -d "$VENV_DIR" ]]  || error "Virtual environment not found at $VENV_DIR."
[[ -f "$ACTIVATE_SH" ]] || error "Could not find activate script at ${ACTIVATE_SH}."
command -v git >/dev/null 2>&1 || error "git is not installed."

# =============================================================================
# System dependencies — fixes OpenCV/MediaPipe shared library errors
# - libGL.so.1 for cv2
# - libGLESv2.so.2 for mediapipe (PersonMaskUltra V2)
# Required by: comfyui-easy-use, comfyui-impact-pack, comfyui-rvtools_v2, ComfyUI_LayerStyle_Advance
# =============================================================================
info "Installing system dependencies (OpenCV + MediaPipe)..."
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq libgl1 libglib2.0-0 libsm6 libxrender1 libxext6 libgles2 libegl1
  info "System dependencies installed."
else
  warn "apt-get not found — skipping system deps. Install libgl1 libgles2 libegl1 manually if cv2/mediapipe fails."
fi

# Activate venv
source "$ACTIVATE_SH"
info "Virtual environment activated."

mkdir -p "$CUSTOM_NODES_DIR"

# =============================================================================
# Helpers
# =============================================================================

install_node() {
  local name="$1"
  local url="$2"
  local dir="${CUSTOM_NODES_DIR}/$(basename "$url" .git)"

  if [[ -d "$dir" && ! -f "$dir/.git/config" ]]; then
    warn "[$name] Found broken folder — removing and re-cloning..."
    rm -rf "$dir"
  fi

  if [[ -d "$dir" ]]; then
    info "[$name] Already installed — pulling latest..."
    git -C "$dir" pull || warn "[$name] git pull failed. Using existing version."
  else
    info "[$name] Cloning from ${url}..."
    if ! git clone --recurse-submodules "$url" "$dir"; then
      warn "[$name] git clone failed. Skipping."
      return
    fi
  fi

  if [[ -f "${dir}/requirements.txt" ]]; then
    info "[$name] Installing Python dependencies..."
    python -m pip install -q -r "${dir}/requirements.txt" \
      || warn "[$name] requirements install had errors. Continuing."
  fi
  if [[ -f "${dir}/install.py" ]]; then
    info "[$name] Running install.py..."
    python "${dir}/install.py" || warn "[$name] install.py had errors. Continuing."
  fi
}

install_node_to_dir() {
  local name="$1"
  local url="$2"
  local folder_name="$3"
  local dir="${CUSTOM_NODES_DIR}/${folder_name}"

  if [[ -d "$dir" && ! -f "$dir/.git/config" ]]; then
    warn "[$name] Found broken folder — removing and re-cloning..."
    rm -rf "$dir"
  fi

  if [[ -d "$dir" ]]; then
    info "[$name] Already installed — pulling latest..."
    git -C "$dir" pull || warn "[$name] git pull failed. Using existing version."
  else
    info "[$name] Cloning from ${url} into ${folder_name}..."
    if ! git clone --recurse-submodules "$url" "$dir"; then
      warn "[$name] git clone failed. Skipping."
      return
    fi
  fi

  if [[ -f "${dir}/requirements.txt" ]]; then
    info "[$name] Installing Python dependencies..."
    python -m pip install -q -r "${dir}/requirements.txt" \
      || warn "[$name] requirements install had errors. Continuing."
  fi
  if [[ -f "${dir}/install.py" ]]; then
    info "[$name] Running install.py..."
    python "${dir}/install.py" || warn "[$name] install.py had errors. Continuing."
  fi
}

migrate_folder_if_needed() {
  local old_name="$1"
  local new_name="$2"
  local old_dir="${CUSTOM_NODES_DIR}/${old_name}"
  local new_dir="${CUSTOM_NODES_DIR}/${new_name}"
  if [[ -d "$old_dir" && ! -d "$new_dir" ]]; then
    info "Renaming '${old_name}' -> '${new_name}' to match ComfyUI pack ID."
    mv "$old_dir" "$new_dir"
  fi
}

patch_rmbg_yolo_placeholder() {
  local file="${CUSTOM_NODES_DIR}/ComfyUI-RMBG/py/AILab_YoloV8.py"

  [[ -f "$file" ]] || {
    warn "[ComfyUI-RMBG] Could not find ${file}; skipping YOLO placeholder patch."
    return
  }

  python - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """    def _resolve_model_path(self, name: str) -> str:\n        return folder_paths.get_full_path_or_raise(\"ultralytics\", name)\n"""
new = """    def _resolve_model_path(self, name: str) -> str:\n        models = self._list_models()\n        if name.startswith(\"Put .pt models into \"):\n            if not models:\n                raise FileNotFoundError(f\"Model in folder 'ultralytics' with filename '{name}' not found.\")\n            name = models[0]\n        return folder_paths.get_full_path_or_raise(\"ultralytics\", name)\n"""

if new in text:
    raise SystemExit(0)
if old not in text:
    raise SystemExit("patch target not found")

path.write_text(text.replace(old, new), encoding="utf-8")
PY

  if [[ $? -eq 0 ]]; then
    info "[ComfyUI-RMBG] Patched AILab_YoloV8 placeholder fallback."
  else
    warn "[ComfyUI-RMBG] Failed to patch AILab_YoloV8 placeholder fallback."
  fi
}

# =============================================================================
# 0. ComfyUI Manager
# =============================================================================
info "Installing/Updating comfyui-manager..."
pip install -U --pre comfyui-manager || warn "comfyui-manager pip install failed."
install_node "ComfyUI Manager" \
  "https://github.com/ltdrdata/ComfyUI-Manager.git"

# =============================================================================
# 1. rgthree-comfy — Power Lora Loader, Image Comparer
# =============================================================================
install_node "rgthree-comfy" \
  "https://github.com/rgthree/rgthree-comfy.git"

# =============================================================================
# 2. JPS Nodes — Latent Switch
# =============================================================================
install_node "JPS Nodes (Latent Switch)" \
  "https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git"

# =============================================================================
# 3. KJNodes — DrawMaskOnImage, PatchSageAttentionKJ
# =============================================================================
install_node "KJNodes" \
  "https://github.com/kijai/ComfyUI-KJNodes.git"

info "[KJNodes] Installing SageAttention dependency..."
pip install -q sageattention || warn "[KJNodes] sageattention install failed. PatchSageAttentionKJ may be unavailable on this system."

# =============================================================================
# 4. Impact Pack — PreviewBridge, Cut By Mask
# =============================================================================
info "[Impact Pack] Pre-installing sam2..."
pip install -q sam2 || warn "[Impact Pack] sam2 pre-install failed."
migrate_folder_if_needed "ComfyUI-Impact-Pack" "comfyui-impact-pack"
install_node_to_dir "Impact Pack" \
  "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" \
  "comfyui-impact-pack"

# =============================================================================
# 5. Easy Use — easy positive
# =============================================================================
migrate_folder_if_needed "ComfyUI-Easy-Use" "comfyui-easy-use"
install_node_to_dir "Easy Use (easy positive)" \
  "https://github.com/yolain/ComfyUI-Easy-Use.git" \
  "comfyui-easy-use"

# =============================================================================
# 6. Easy SAM3 — easy sam3ModelLoader, easy sam3ImageSegmentation
# =============================================================================
migrate_folder_if_needed "ComfyUI-Easy-Sam3" "comfyui-easy-sam3"
install_node_to_dir "Easy SAM3 (sam3ModelLoader + sam3ImageSegmentation)" \
  "https://github.com/yolain/ComfyUI-Easy-Sam3.git" \
  "comfyui-easy-sam3"

# =============================================================================
# 7. LayerStyle Advance — PersonMaskUltra V2
#    FIX: Uses its OWN separate repo: chflame163/ComfyUI_LayerStyle_Advance
#    (NOT the base ComfyUI_LayerStyle repo cloned into this folder name)
# =============================================================================
info "[LayerStyle Advance] Pre-installing dependencies..."
# opencv-contrib-python is required for cv2.ximgproc.guidedFilter (PersonMaskUltra V2)
# Plain opencv-python / opencv-python-headless do NOT include ximgproc — remove them first
pip uninstall -y opencv-python opencv-python-headless 2>/dev/null || true
pip install -q opencv-contrib-python || warn "[LayerStyle Advance] opencv-contrib-python install failed."
pip install -q scikit-image transparent-background || warn "[LayerStyle Advance] scikit-image/transparent-background pre-install failed."
# Prefer onnxruntime-gpu on CUDA systems; don't overwrite it with the CPU-only build
if python -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
  pip install -q onnxruntime-gpu || warn "[LayerStyle Advance] onnxruntime-gpu pre-install failed."
elif ! pip show onnxruntime-gpu &>/dev/null && ! pip show onnxruntime &>/dev/null; then
  pip install -q onnxruntime || warn "[LayerStyle Advance] onnxruntime pre-install failed."
fi

# Remove wrong installation if base LayerStyle was previously cloned here
ADVANCE_DIR="${CUSTOM_NODES_DIR}/ComfyUI_LayerStyle_Advance"
if [[ -d "$ADVANCE_DIR" ]]; then
  REMOTE=$(git -C "$ADVANCE_DIR" remote get-url origin 2>/dev/null || true)
  # If the remote is the base LayerStyle (not Advance), remove and re-clone
  if [[ "$REMOTE" == "https://github.com/chflame163/ComfyUI_LayerStyle.git" ]]; then
    warn "[LayerStyle Advance] Wrong repo detected — removing and cloning correct one..."
    rm -rf "$ADVANCE_DIR"
  fi
fi

install_node_to_dir "LayerStyle Advance (PersonMaskUltra V2)" \
  "https://github.com/chflame163/ComfyUI_LayerStyle_Advance.git" \
  "ComfyUI_LayerStyle_Advance"

# =============================================================================
# 8. RvTools v2 — Image to RGB [RvTools]
# =============================================================================
OLD_RV="${CUSTOM_NODES_DIR}/comfyui-rvtools"
if [[ -d "$OLD_RV" ]]; then
  warn "[RvTools] Removing old/wrong folder: ${OLD_RV}"
  rm -rf "$OLD_RV"
fi
install_node_to_dir "RvTools v2 (Image to RGB)" \
  "https://github.com/r-vage/ComfyUI-RvTools_v2.git" \
  "comfyui-rvtools_v2"

# =============================================================================
# 9. Masquerade Nodes — Cut By Mask
# =============================================================================
install_node "Masquerade Nodes (Cut By Mask)" \
  "https://github.com/BadCafeCode/masquerade-nodes-comfyui.git"

# =============================================================================
# 10. LoadImageWithFilename
# =============================================================================
install_node "LoadImageWithFilename" \
  "https://github.com/thalismind/ComfyUI-LoadImageWithFilename.git"

# =============================================================================
# 11. alex-seedvr-node — SeedVR2, SeedVR2BlockSwap
# =============================================================================
install_node "alex-seedvr-node (SeedVR2 + SeedVR2BlockSwap)" \
  "https://github.com/shangeethAlex/alex-seedvr-node.git"

# =============================================================================
# 12. comfyui_layerstyle (BASE) — MaskPreview, ColorImage V2, CropByMask V2,
#     ImageScaleByAspectRatio V2, PurgeVRAM V2
#     NOTE: This is the BASE LayerStyle repo, separate from LayerStyle_Advance
#           installed in section 7 above.
# =============================================================================
install_node_to_dir "LayerStyle Base (MaskPreview, ColorImageV2, CropByMaskV2, ImageScaleByAspectRatioV2, PurgeVRAMV2)" \
  "https://github.com/chflame163/ComfyUI_LayerStyle.git" \
  "ComfyUI_LayerStyle"

# =============================================================================
# 13. comfyui-rmbg — ClothesSegment
# =============================================================================
install_node_to_dir "ComfyUI-RMBG (ClothesSegment)" \
  "https://github.com/1038lab/ComfyUI-RMBG.git" \
  "ComfyUI-RMBG"

info "[ComfyUI-RMBG] Installing optional ultralytics dependency for YOLO nodes..."
pip install -q ultralytics --no-deps || warn "[ComfyUI-RMBG] ultralytics install failed. YOLO nodes may be unavailable."
patch_rmbg_yolo_placeholder

# =============================================================================
# 14. Flux2Klein Enhancer
# =============================================================================
install_node "Flux2Klein Enhancer" \
  "https://github.com/capitan01R/ComfyUI-Flux2Klein-Enhancer.git"

# =============================================================================
# 15. Inpaint CropAndStitch
# =============================================================================
install_node "Inpaint CropAndStitch" \
  "https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch.git"

# =============================================================================
# 16. ComfyUI-NAG
# =============================================================================
# Replace the upstream repo with the Flux 2 Klein compatible fork if needed.
NAG_DIR="${CUSTOM_NODES_DIR}/ComfyUI-NAG"
if [[ -d "$NAG_DIR" ]]; then
  NAG_REMOTE=$(git -C "$NAG_DIR" remote get-url origin 2>/dev/null || true)
  if [[ "$NAG_REMOTE" == "https://github.com/ChenDarYen/ComfyUI-NAG.git" ]]; then
    warn "[ComfyUI-NAG] Replacing upstream repo with BigStationW fork required by this workflow..."
    rm -rf "$NAG_DIR"
  fi
fi
install_node "ComfyUI-NAG" \
  "https://github.com/BigStationW/ComfyUI-NAG.git"

# =============================================================================
# 17. Scale Image to Total Pixels Advanced
# =============================================================================
install_node "Scale Image to Total Pixels Advanced" \
  "https://github.com/BigStationW/ComfyUi-Scale-Image-to-Total-Pixels-Advanced.git"

# =============================================================================
# 18. ComfyUI-Florence2
# =============================================================================
install_node "ComfyUI-Florence2" \
  "https://github.com/kijai/ComfyUI-Florence2.git"

# =============================================================================
# Done!
# =============================================================================
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Custom nodes installation complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Installed into: $CUSTOM_NODES_DIR"
echo ""
echo "  ⚠  SAM3 nodes require the sam3.pt model file."
echo "     Accept access at: https://huggingface.co/facebook/sam3"
echo "     Then download it to: ~/ComfyUI/models/sam3/sam3.pt"
echo ""
echo "  Restart ComfyUI:"
echo "    cd ~/ComfyUI && ./start.sh --enable-manager"
echo ""
