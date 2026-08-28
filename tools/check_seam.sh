#!/usr/bin/env bash
# check_seam.sh — the library's one architectural invariant, enforced.
#
# smalt is portable because the operating system is confined to platform
# overlay directories: `src/<area>/<os>/`. Everything else compiles for
# every target. That sentence is worth nothing as prose — a single
# `extern "C" from "user32"` in a file above the seam makes the Linux
# build fail at the linker, a hundred files away from the cause, and
# nothing before this script would have said so.
#
# Three rules, each of which has a way of being violated by accident:
#
#   1. No OS import outside an overlay. A `native fn` / `@link_name` /
#      `extern "C" from` is a symbol some libc, DLL or shared object has
#      to provide, so the file that writes one belongs to a platform.
#   2. No `use` path names an operating system. The overlay is chosen by
#      `--target`, so a path that spells `windows` is a file that
#      compiles for one platform wherever it happens to sit.
#   3. Every seam is implemented for every platform. A `sys_*.axle`
#      present in one overlay and missing from another is a port with a
#      hole, and the compiler only says so when someone builds for the
#      platform that is missing it.
#
# `--selftest` plants each violation in a scratch copy and fails if the
# check passes on it: a gate nobody has watched reject something is a
# gate that may be looking for nothing.
#
# Usage:  tools/check_seam.sh [<repo-root>]
#         tools/check_seam.sh --selftest

set -uo pipefail

# The directory names that make a directory a platform overlay. The same
# list the compiler resolves against; there is no third place holding it.
OVERLAY_DIRS='windows|linux|macos'

note() { printf '%s\n' "$*" >&2; }

# Every `.axle` under `src/` that is NOT inside an overlay directory —
# the portable half of the library, which is what all three rules are
# about.
portable_files() {
    local root=$1
    find "$root/src" -name '*.axle' \
        | grep -Ev "/($OVERLAY_DIRS)/" \
        | sort
}

# Rule 1 — an OS import outside an overlay.
check_no_os_import() {
    local root=$1 hits
    hits=$(portable_files "$root" | xargs grep -nE 'extern[[:space:]]+"C"[[:space:]]+from|@link_name|native[[:space:]]+fn' 2>/dev/null)
    if [ -n "$hits" ]; then
        note "FAIL: an OS import outside a platform overlay:"
        note "$hits"
        return 1
    fi
    return 0
}

# Rule 2 — a `use` path that names an operating system. Checked over the
# whole tree, overlays included: a backend that reaches into another
# backend's directory is the same mistake pointing the other way.
check_no_platform_in_use() {
    local root=$1 hits
    hits=$(find "$root/src" -name '*.axle' -print0 \
        | xargs -0 grep -nE "^use .*::($OVERLAY_DIRS)::" 2>/dev/null)
    if [ -n "$hits" ]; then
        note "FAIL: a use path names an operating system:"
        note "$hits"
        return 1
    fi
    return 0
}

# Rule 3 — a seam file present in one overlay and missing from another.
# Only `sys_*.axle` is compared: those are the seam, and a backend's own
# private modules are deliberately not symmetric.
check_seams_are_complete() {
    local root=$1 rc=0
    local parent overlays base
    # Each directory that holds at least one overlay.
    for parent in $(find "$root/src" -type d -regextype posix-extended -regex ".*/($OVERLAY_DIRS)" \
                    | xargs -r -n1 dirname | sort -u); do
        overlays=$(find "$parent" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended \
                   -regex ".*/($OVERLAY_DIRS)" | sort)
        # The union of every seam name any platform implements here.
        local names
        names=$(for d in $overlays; do
                    find "$d" -maxdepth 1 -name 'sys_*.axle' -exec basename {} \;
                done | sort -u)
        for d in $overlays; do
            for base in $names; do
                if [ ! -f "$d/$base" ]; then
                    note "FAIL: $d/$base is missing — the seam is implemented for the other platforms here"
                    rc=1
                fi
            done
        done
    done
    return $rc
}

run_checks() {
    local root=$1 rc=0
    check_no_os_import "$root"       || rc=1
    check_no_platform_in_use "$root" || rc=1
    check_seams_are_complete "$root" || rc=1
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

    # Rule 2: a use path naming a platform.
    printf '\nuse crate::platform::windows::sys_app::SysApp;\n' >> "$tmp/src/core/timer.axle"
    if run_checks "$tmp" >/dev/null 2>&1; then
        note "SELFTEST FAIL: rule 2 accepted a use path naming a platform"
        rc=1
    fi
    rm -rf "$tmp/src"; cp -r "$root/src" "$tmp/src"

    # Rule 3: a seam implemented for one platform only.
    rm -f "$tmp"/src/platform/linux/sys_clock.axle
    if run_checks "$tmp" >/dev/null 2>&1; then
        note "SELFTEST FAIL: rule 3 accepted a seam missing from a platform"
        rc=1
    fi

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
        echo "check_seam OK — the OS is confined to the platform overlays"
        exit 0
    fi
    exit 1
}

main "$@"
