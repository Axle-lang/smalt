#!/usr/bin/env bash
# check_seam.sh — the library's one architectural invariant, enforced.
#
# smalt is portable because the operating system is confined to the port
# directories `axle.toml` declares: `src/<area>/<port-dir>/`. Everything
# else compiles for every target. That sentence is worth nothing as prose
# — a single `extern "C" from "user32"` in a file above the seam makes
# the Linux build fail at the linker, a hundred files away from the
# cause, and nothing before this script would have said so.
#
# Two rules, each of which has a way of being violated by accident:
#
#   1. No OS import outside a port directory. A `native fn` /
#      `@link_name` / `extern "C" from` is a symbol some libc, DLL or
#      shared object has to provide, so the file that writes one belongs
#      to a port.
#   2. No `use` path crosses into a port that is not the file's own.
#      The port is chosen by the target and the features, so a portable
#      file that spells `win32` compiles for one platform, and a
#      backend that names another backend's module is the same mistake
#      pointing the other way. A port naming its own module is how a
#      port is written.
#
# The third rule this script used to carry — every seam implemented for
# every platform — is the compiler's now, and better held there: a port
# is *several* directories, so "every directory has every seam" was never
# the right shape (`posix/` holds the clock both Linux ports share and no
# window at all). `axle ports` prints the table with a tick per seam per
# port, and a build refuses an incomplete one.
#
# `--selftest` plants each violation in a scratch copy and fails if the
# check passes on it: a gate nobody has watched reject something is a
# gate that may be looking for nothing.
#
# Usage:  tools/check_seam.sh [<repo-root>]
#         tools/check_seam.sh --selftest

set -uo pipefail

# The directory names that make a directory a port's. Read out of
# `axle.toml`, which is where the compiler reads them: a list kept here
# as well would be a second place to forget, and the failure would be
# this script silently checking nothing.
port_dirs() {
    local root=$1
    sed -n 's/^dirs *= *\[\(.*\)\]/\1/p' "$root/axle.toml" \
        | tr -d ' "' | tr ',' '\n' | grep -v '^$' | sort -u | paste -sd'|'
}

note() { printf '%s\n' "$*" >&2; }
# Every `.axle` under `src/` that is NOT inside a port directory — the
# portable half of the library, which is what both rules are about.

portable_files() {
    local root=$1
    find "$root/src" -name '*.axle' \
        | grep -Ev "/($(port_dirs "$root"))/" \
        | sort
}

# Rule 1 — an OS import outside a port directory.
check_no_os_import() {
    local root=$1 hits
    hits=$(portable_files "$root" | xargs grep -nE 'extern[[:space:]]+"C"[[:space:]]+from|@link_name|native[[:space:]]+fn' 2>/dev/null)
    if [ -n "$hits" ]; then
        note "FAIL: an OS import outside a port directory:"
        note "$hits"
        return 1
    fi
    return 0
}

# Rule 2 — a `use` path that crosses into a port that is not the
# file's own. Checked over the whole tree, ports included: a backend
# reaching into another backend is the same mistake pointing the other way.
check_no_platform_in_use() {
    local root=$1 rc=0 dirs file own hits
    dirs=$(port_dirs "$root")
    while IFS= read -r file; do
        # The port directory this file itself lives in, if any. A backend
        # naming its *own* private module is how a port is written; what
        # this rule is about is a path that crosses — a portable file
        # reaching into a port, or one port reaching into another.
        own=$(printf '%s' "$file" | grep -oE "/($dirs)/" | head -1 | tr -d '/')
        hits=$(grep -nE "^use .*::($dirs)::" "$file" 2>/dev/null \
               | { if [ -n "$own" ]; then grep -vE "::$own::"; else cat; fi; })
        if [ -n "$hits" ]; then
            note "FAIL: $file names a port directory that is not its own:"
            note "$hits"
            rc=1
        fi
    done < <(find "$root/src" -name '*.axle' | sort)
    return $rc
}

run_checks() {
    local root=$1 rc=0
    check_no_os_import "$root"       || rc=1
    check_no_platform_in_use "$root" || rc=1
    return $rc
}

# Scratch tree the selftest plants its violations in. File-scope rather
# than local to the function, because the EXIT trap that removes it runs
# after the function has returned — and under `set -u` a trap naming a
# dead local is an error printed on a successful run.
SELFTEST_DIR=""

cleanup_selftest() {
    if [ -n "$SELFTEST_DIR" ]; then
        rm -rf "$SELFTEST_DIR"
    fi
}

selftest() {
    local root=$1 rc=0 tmp
    SELFTEST_DIR=$(mktemp -d)
    tmp="$SELFTEST_DIR"
    trap cleanup_selftest EXIT

    # It must accept the tree as it stands.
    cp -r "$root/src" "$tmp/src"
    cp "$root/axle.toml" "$tmp/axle.toml"
    if ! run_checks "$tmp" >/dev/null 2>&1; then
        note "SELFTEST FAIL: the unmodified tree must pass"
        rc=1
    fi

    # Rule 1: an OS import in a portable file.
    printf '\nextern "C" from "user32" {\n    fn Beep(a : i32, b : i32) : i32;\n}\n' \
        >> "$tmp/src/core/timer.axle"
    if run_checks "$tmp" >/dev/null 2>&1; then
        note "SELFTEST FAIL: rule 1 accepted an OS import in a portable file"
        rc=1
    fi
    rm -rf "$tmp/src"; cp -r "$root/src" "$tmp/src"

    # Rule 2: a portable file naming a port directory.
    printf '\nuse crate::platform::win32::sys_app::SysApp;\n' >> "$tmp/src/core/timer.axle"
    if run_checks "$tmp" >/dev/null 2>&1; then
        note "SELFTEST FAIL: rule 2 accepted a use path naming a platform"
        rc=1
    fi
    rm -rf "$tmp/src"; cp -r "$root/src" "$tmp/src"

    # Rule 2, the other direction: one port reaching into another. The
    # half a rule that only tested portable files would have missed, and
    # the half that is easiest to write by accident when a second
    # backend is being written beside a first.
    printf '\nuse crate::video::x11::x_keymap::XKeymap;\n' \
        >> "$tmp/src/video/wayland/wl_input.axle"
    if run_checks "$tmp" >/dev/null 2>&1; then
        note "SELFTEST FAIL: rule 2 accepted one port reaching into another"
        rc=1
    fi
    rm -rf "$tmp/src"; cp -r "$root/src" "$tmp/src"

    if [ $rc -eq 0 ]; then
        echo "check_seam selftest OK — every rule rejects what it is for"
    fi
    return $rc
}

main() {
    if [ "${1:-}" = "--selftest" ]; then
        selftest "$(cd "$(dirname "$0")/.." && pwd)"
        exit $?
    fi
    local root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
    if run_checks "$root"; then
        echo "check_seam OK — the OS is confined to the port directories"
        exit 0
    fi
    exit 1
}

main "$@"
