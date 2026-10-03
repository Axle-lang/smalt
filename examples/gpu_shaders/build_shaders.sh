#!/usr/bin/env bash
# build_shaders.sh — regenerate src/shaders.axle from shaders/.
#
# Usage:  ./build_shaders.sh <path to glslang>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
glslang="${1:?usage: ./build_shaders.sh <path to glslang>}"
# PYTHON overrides the interpreter; otherwise python3, or python where that is all there is.
python="${PYTHON:-$(command -v python3 || command -v python)}"
cd "$here"
"$python" ../../tools/spirv_tables.py --glslang "$glslang" --include shaders -I ../../shaders \
    --out src/shaders.axle --class Shaders --visibility "pub(crate)" \
    --header shaders/spirv_header.txt --doc "gpu_shaders' compiled stages." \
    "background.frag:background:The texture behind everything" \
    "tint.vert:tintVert:The mesh shader's vertex stage" \
    "tint.frag:tintFrag:The mesh shader's fragment stage" \
    "invert.frag:invert:A pass that inverts the frame before it" \
    "choose.frag:choose:The last pass, choosing by depth"
