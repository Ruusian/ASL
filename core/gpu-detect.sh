#!/bin/bash
# ASL: report the selected safe GPU profile.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gpu-profile.sh
source "$SCRIPT_DIR/gpu-profile.sh"
asl_gpu_report

