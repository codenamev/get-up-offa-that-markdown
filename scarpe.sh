#!/bin/sh
# Runs Scarpe from your clone without disturbing the person at this machine: dialogs, sounds and
# the clipboard go to Scarpe's stand-ins, and the app's HOME is a scratch folder of its own.
APP_DIR="$(cd "$(dirname "$0")" && pwd)"                  # the folder this script sits in
export BUNDLE_GEMFILE="$APP_DIR/Gemfile"
SCARPE="${SCARPE:-$(bundle exec ruby -e 'print Gem::Specification.find_by_name("scarpe").full_gem_path')}"
BOX="${SCARPE_HOME:-${TMPDIR:-/tmp}/scarpe-home-$(basename "$APP_DIR")}"  # this app's HOME
RUBY="$(bundle exec ruby -e 'print RbConfig.ruby')"       # resolve before changing HOME
mkdir -p "$BOX"
exec env PATH="$SCARPE/spec/support/fakebin:$PATH" HOME="$BOX" \
  SPEC_TRAP_FILE="$BOX/trapped.txt" SPEC_CLIPBOARD_FILE="$BOX/clipboard.txt" \
  RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" \
  SCARPE="$SCARPE" BUNDLE_GEMFILE="$APP_DIR/Gemfile" "$RUBY" "$SCARPE/exe/scarpe" "$@" --dev
