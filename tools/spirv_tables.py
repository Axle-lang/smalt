#!/usr/bin/env python3
"""spirv_tables.py — compile GLSL with glslang and write the SPIR-V as an Axle table.

Vulkan takes shaders as SPIR-V words, and an Axle program carries them as array
literals so that it builds with the Axle compiler and nothing else. This is the
step between the two, written down instead of done by hand:

    python3 tools/spirv_tables.py --glslang <glslang> --include shaders \\
        --out src/gpu/vk/spirv.axle --class Spirv --visibility "pub(crate)" \\
        --header shaders/spirv_header.txt \\
        scene.vert:sceneVert:"The lit scene's vertex stage" ...

Each module argument is `file:function:description`; the file is relative to the
`--include` directory. A program's own shaders include smalt's `frame.glsl` and
`post.glsl` by adding smalt's `shaders/` with `-I`. A module is compiled with `-V --target-env vulkan1.0`, its
words are written eight to a line as signed decimals (SPIR-V words use all 32 bits,
and an Axle array literal takes its element type from its values), and a
`<function>Bytes()` beside it answers its size.

glslang is not part of the build: it is needed only when a shader changes. Any
release of it will do (`glslang`, or the older name `glslangValidator`).
"""

import argparse
import os
import struct
import subprocess
import sys
import tempfile

SPIRV_MAGIC = 0x07230203


def compile_module(glslang, includes, source):
    """Compile one stage to SPIR-V and return its words as signed 32-bit ints."""
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "module.spv")
        cmd = [glslang, "-V", "--target-env", "vulkan1.0"]
        cmd += ["-I" + d for d in includes]
        cmd += [source, "-o", out]
        run = subprocess.run(cmd, capture_output=True, text=True)
        if run.returncode != 0:
            sys.stderr.write(run.stdout + run.stderr)
            raise SystemExit("glslang failed on " + source)
        with open(out, "rb") as f:
            data = f.read()
    if len(data) < 4 or len(data) % 4 != 0:
        raise SystemExit(source + ": SPIR-V is not a whole number of words")
    if struct.unpack("<I", data[:4])[0] != SPIRV_MAGIC:
        raise SystemExit(source + ": glslang's output is not little-endian SPIR-V")
    return list(struct.unpack("<%di" % (len(data) // 4), data))


def table(name, description, words, visibility, source):
    """The two functions for one module: its words, and its size in bytes."""
    lines = []
    lines.append("    /** %s — `%s`, %d words. */" % (description, source, len(words)))
    lines.append("    %s static fn %s() : i32[] {" % (visibility, name))
    lines.append("        return [")
    for i in range(0, len(words), 8):
        row = ", ".join(str(w) for w in words[i:i + 8])
        tail = "," if i + 8 < len(words) else ""
        lines.append("            " + row + tail)
    lines.append("        ];")
    lines.append("    }")
    lines.append("")
    lines.append("    /** Bytes in `%s()` — what `VkShaderModuleCreateInfo.codeSize` wants. */" % name)
    lines.append("    %s static fn %sBytes() : i64 {" % (visibility, name))
    lines.append("        return %d;" % (len(words) * 4))
    lines.append("    }")
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--glslang", required=True, help="path to glslang / glslangValidator")
    ap.add_argument("--include", required=True, help="the shader directory, also the -I path")
    ap.add_argument("-I", dest="extra", action="append", default=[],
                    help="another include directory (smalt's shaders/, for frame.glsl and post.glsl)")
    ap.add_argument("--out", required=True, help="the .axle file to write")
    ap.add_argument("--class", dest="cls", required=True, help="the class the tables go in")
    ap.add_argument("--visibility", default="pub(crate)", help="of the class and its functions")
    ap.add_argument("--header", required=True, help="the file's leading comment, as text")
    ap.add_argument("--doc", default="The compiled shader modules.", help="the class's doc line")
    ap.add_argument("modules", nargs="+", help="file:function:description")
    args = ap.parse_args()

    out = []
    with open(args.header, encoding="utf-8") as f:
        header = f.read()
    out.extend(header.rstrip("\n").split("\n"))
    out.append("")
    out.append("/** %s */" % args.doc)
    out.append("%s class %s {" % (args.visibility, args.cls))
    first = True
    for spec in args.modules:
        source, name, description = spec.split(":", 2)
        includes = [args.include] + args.extra
        words = compile_module(args.glslang, includes, os.path.join(args.include, source))
        if not first:
            out.append("")
        first = False
        out.extend(table(name, description, words, args.visibility, args.include.rstrip("/") + "/" + source))
    out.append("}")
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
