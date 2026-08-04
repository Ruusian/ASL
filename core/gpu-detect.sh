#!/bin/bash
# AndroidLinux-SuperKit: report the selected safe GPU profile.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gpu-profile.sh
source "$SCRIPT_DIR/gpu-profile.sh"
superkit_gpu_report
