# Our fork of elixir-crab/gpui (branch hover-styles), consumed by trip-service-cli/apps/tsg.
set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Regenerate the Rust from the Elixir schemas (run after editing apps/gpui/lib/gpui/schema.ex)
gen:
    mix rustq.gen

# Fail if generated Rust is stale
gen-check:
    mix rustq.gen --check

# Elixir-side checks (no native build)
test:
    mix format --check-formatted
    mix test --exclude native

# Full validation suite (slow, needs the native toolchain)
ci:
    mix ci

# Typecheck the native host with the pinned toolchain
rust-check:
    cargo check --features gpui-component-host --manifest-path apps/gpui_native/native/Cargo.toml

# After pushing Rust changes: pin the sibling crates (resolved by git, from this branch) in the
# standalone lock used by sparse consumers. Commit and push the result, then run
# `just gpui-update` in trip-service-cli/apps/tsg.
gpui-lock:
    #!/usr/bin/env bash
    set -euo pipefail
    git diff --quiet && git diff --cached --quiet || { echo "commit and push first"; exit 1; }
    rm -rf /tmp/gpui-lock && mkdir /tmp/gpui-lock
    cp -r apps/gpui_native/native /tmp/gpui-lock/native
    rm -rf /tmp/gpui-lock/native/target
    cd /tmp/gpui-lock/native
    cargo update -p gpui_core -p gpui_components
    cp Cargo.lock "{{justfile_directory()}}/apps/gpui_native/native/Cargo.lock"
    echo "Updated apps/gpui_native/native/Cargo.lock; commit and push it."

# Pull the upstream project's changes into this branch
sync-upstream:
    git fetch upstream
    git merge upstream/main

push:
    git push origin hover-styles
