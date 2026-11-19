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

# After pushing Rust changes: point the standalone lock (used by sparse consumers) at the
# pushed commit for the sibling crates. Only those two source lines change, so the pinned Zed
# revision is untouched. Commit and push the result, then run `just gpui-update` in
# trip-service-cli/apps/tsg.
gpui-lock:
    #!/usr/bin/env bash
    set -euo pipefail
    git diff --quiet && git diff --cached --quiet || { echo "commit and push first"; exit 1; }
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/hover-styles)" ] || { echo "push first"; exit 1; }
    sha=$(git rev-parse HEAD)
    sed -i -E "s|(rockneurotiko/gpui\?branch=hover-styles#)[0-9a-f]+|\1${sha}|" apps/gpui_native/native/Cargo.lock
    echo "Pinned crates to ${sha}; commit and push apps/gpui_native/native/Cargo.lock."

# Pull the upstream project's changes into this branch
sync-upstream:
    git fetch upstream
    git merge upstream/main

push:
    git push origin hover-styles
