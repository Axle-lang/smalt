#!/usr/bin/env bash
# build_shaders.sh — regenerate src/gpu/vk/spirv.axle from shaders/.
#
# Usage:  tools/build_shaders.sh <path to glslang>
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
glslang="${1:?usage: tools/build_shaders.sh <path to glslang>}"
# PYTHON overrides the interpreter; otherwise python3, or python where that is all there is.
python="${PYTHON:-$(command -v python3 || command -v python)}"
cd "$root"
"$python" tools/spirv_tables.py --glslang "$glslang" --include shaders \
    --out src/gpu/vk/spirv.axle --class Spirv --visibility "pub(crate)" \
    --header shaders/spirv_header.txt \
    "scene.vert:sceneVert:The lit scene's vertex stage" \
    "scene.frag:sceneFrag:The lit scene's fragment stage" \
    "overlay.vert:overlayVert:The full-screen triangle — the overlay's, and every pass's" \
    "overlay.frag:overlayFrag:The 2-D overlay's colour-keyed fragment stage" \
    "copy.frag:copyFrag:The 3-D frame onto the window, when no pass of the program's does it"
