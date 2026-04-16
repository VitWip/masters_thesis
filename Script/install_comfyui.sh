#!/usr/bin/env bash
# =============================================================================
# ComfyUI Installer — Linux + NVIDIA
# =============================================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Config — edit these if you want different paths ──────────────────────────
INSTALL_DIR="${HOME}/ComfyUI"
PYTHON_BIN="${PYTHON_BIN:-python3}"   # override with: PYTHON_BIN=python3.12 ./install_comfyui.sh
VENV_DIR="${INSTALL_DIR}/.venv"

# =============================================================================
# 1. Prerequisites check
# =============================================================================
info "Checking prerequisites..."

command -v git  >/dev/null 2>&1 || error "git is not installed. Run: sudo apt install git"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || error "$PYTHON_BIN not found. Install Python 3.12 or 3.13 first."

PY_VER=$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
info "Using Python $PY_VER  ($("$PYTHON_BIN" -c 'import sys; print(sys.executable)'))"

# Warn on Python versions outside the sweet spot
python_version_check() {
  local major minor
  major=$("$PYTHON_BIN" -c 'import sys; print(sys.version_info.major)')
  minor=$("$PYTHON_BIN" -c 'import sys; print(sys.version_info.minor)')
  if [[ "$major" -lt 3 ]] || [[ "$major" -eq 3 && "$minor" -lt 12 ]]; then
    warn "Python $PY_VER may be too old. Recommended: 3.12 or 3.13."
  fi
  if [[ "$major" -eq 3 && "$minor" -ge 14 ]]; then
    warn "Python $PY_VER is experimental for ComfyUI. Some custom nodes may fail."
  fi
}
python_version_check

# =============================================================================
# 2. Clone ComfyUI
# =============================================================================
if [[ -d "$INSTALL_DIR" ]]; then
  warn "Directory $INSTALL_DIR already exists — pulling latest changes instead."
  git -C "$INSTALL_DIR" pull
else
  info "Cloning ComfyUI into $INSTALL_DIR ..."
  git clone https://github.com/comfyanonymous/ComfyUI.git "$INSTALL_DIR"
fi

# =============================================================================
# 3. Create virtual environment
# =============================================================================
if [[ ! -d "$VENV_DIR" ]]; then
  info "Creating Python virtual environment at $VENV_DIR ..."
  "$PYTHON_BIN" -m venv "$VENV_DIR"
else
  info "Virtual environment already exists — reusing it."
fi

# Activate venv for the rest of the script
# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"
info "Virtual environment activated."

# =============================================================================
# 4. Install PyTorch (NVIDIA CUDA 12.8)
# =============================================================================
info "Installing PyTorch with CUDA 12.8 support..."
pip install --upgrade pip --quiet

# cu130 wheels do not exist yet; cu128 is the latest stable CUDA index.
# Use --index-url as primary so pip never silently falls back to a CPU-only
# PyPI build when no CUDA wheel is found.
pip install torch torchvision torchaudio \
  --index-url https://download.pytorch.org/whl/cu128

# Quick CUDA sanity check
info "Verifying CUDA availability..."
python - <<'EOF'
import torch
if torch.cuda.is_available():
    print(f"  ✓ CUDA is available — {torch.cuda.get_device_name(0)}")
    print(f"  ✓ PyTorch {torch.__version__}")
else:
    print("  ✗ CUDA not available. Check your NVIDIA driver and CUDA installation.")
    print("    If you see 'Torch not compiled with CUDA enabled', run:")
    print("      pip uninstall torch torchvision torchaudio")
    print("    Then re-run this script with the correct CUDA index:")
    print("      pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128")
EOF

# =============================================================================
# 5. Install ComfyUI dependencies
# =============================================================================
info "Installing ComfyUI Python dependencies..."
pip install -r "${INSTALL_DIR}/requirements.txt"

# =============================================================================
# 6. Create model directories
# =============================================================================
info "Creating model directories..."
mkdir -p \
  "${INSTALL_DIR}/models/checkpoints" \
  "${INSTALL_DIR}/models/vae" \
  "${INSTALL_DIR}/models/loras" \
  "${INSTALL_DIR}/models/embeddings" \
  "${INSTALL_DIR}/models/controlnet" \
  "${INSTALL_DIR}/models/upscale_models"

# =============================================================================
# 7. Create a handy launch script
# =============================================================================
LAUNCH_SCRIPT="${INSTALL_DIR}/start.sh"
cat > "$LAUNCH_SCRIPT" <<LAUNCH
#!/usr/bin/env bash
# Launch ComfyUI — generated by install_comfyui.sh
source "${VENV_DIR}/bin/activate"
cd "${INSTALL_DIR}"
python main.py "\$@"
LAUNCH
chmod +x "$LAUNCH_SCRIPT"

# =============================================================================
# Done!
# =============================================================================
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  ComfyUI installation complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Install location : $INSTALL_DIR"
echo "  Launch command   : ${LAUNCH_SCRIPT}"
echo ""
echo "  Place your models here:"
echo "    Checkpoints → ${INSTALL_DIR}/models/checkpoints"
echo "    VAE         → ${INSTALL_DIR}/models/vae"
echo "    LoRAs       → ${INSTALL_DIR}/models/loras"
echo ""
echo "  To start ComfyUI:"
echo "    cd $INSTALL_DIR && ./start.sh"
echo "  Or with extra flags, e.g. custom port:"
echo "    ./start.sh --port 8189"
echo ""
