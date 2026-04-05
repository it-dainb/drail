#!/bin/bash
set -euo pipefail

TARGET_DIR="${DRAIL_INSTALL_DIR:-${HOME}/.local/bin}"
TARGET_PATH="${TARGET_DIR}/drail"
SOURCE_PATH="${DRAIL_INSTALL_SOURCE:-$(pwd)/target/release/drail}"
DRY_RUN="${DRAIL_INSTALL_DRY_RUN:-0}"
VERIFY_ONLY="${DRAIL_INSTALL_VERIFY_ONLY:-0}"
SKIP_VERIFY="${DRAIL_INSTALL_SKIP_VERIFY:-0}"

path_contains_dir() {
    case ":${PATH}:" in
        *:"$1":*) return 0 ;;
        *) return 1 ;;
    esac
}

print_path_guidance() {
    printf 'Add this directory to your PATH if needed:\n'
    printf '  export PATH="%s:$PATH"\n' "$TARGET_DIR"
}

verify_install() {
    if [ "$SKIP_VERIFY" = "1" ]; then
        printf 'Skipping CLI verification\n'
        return 0
    fi

    printf 'Verifying drail CLI at %s\n' "$TARGET_PATH"
    version_output="$($TARGET_PATH --version)"
    printf 'Verified drail CLI: %s\n' "$version_output"
}

printf 'Installing drail CLI to %s\n' "$TARGET_PATH"

if [ "$DRY_RUN" = "1" ]; then
    printf 'Dry run: would create %s if needed\n' "$TARGET_DIR"
    printf 'Dry run: would install from %s\n' "$SOURCE_PATH"
    printf 'Dry run: would verify with %s --version\n' "$TARGET_PATH"
    printf 'Cargo installs do not support postinstall hooks. After cargo install, run: drail install-skill\n'
    if ! path_contains_dir "$TARGET_DIR"; then
        print_path_guidance
    fi
    exit 0
fi

if [ "$VERIFY_ONLY" = "1" ]; then
    verify_install
    exit 0
fi

if [ ! -f "$SOURCE_PATH" ]; then
    printf 'Error: source binary not found at %s\n' "$SOURCE_PATH" >&2
    printf 'Build drail first (for example: cargo build --release).\n' >&2
    exit 1
fi

mkdir -p "$TARGET_DIR"

TMP_PATH="${TARGET_PATH}.tmp.$$"
cp "$SOURCE_PATH" "$TMP_PATH"
chmod +x "$TMP_PATH"
mv "$TMP_PATH" "$TARGET_PATH"

printf 'Installed drail CLI to %s\n' "$TARGET_PATH"
verify_install
printf 'To install skills after cargo install, run: drail install-skill\n'
if ! path_contains_dir "$TARGET_DIR"; then
    print_path_guidance
fi
