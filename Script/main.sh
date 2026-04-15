#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCRIPTS=(
  "install_comfyui.sh"
  "install_custom_nodes.sh"
  "install_flux_models.sh"
)

for script in "${SCRIPTS[@]}"; do
  target="${SCRIPT_DIR}/${script}"

  [[ -f "$target" ]] || error "Missing script: ${target}"

  info "Running ${script} ..."
  bash "$target"
done

info "All install scripts completed successfully."