#!/bin/bash

set -euo pipefail

abort() {
  printf 'Fatal error: %s\n' "$1" 1>&2
  exit 2
}

install-dune() {
  curl -fsSL https://get.dune.build/install | sh
}

lock() {
  (set -x; cd "$SETUPDUNEDIR" && dune pkg lock)
}

lazy-update-depexts() {
  case "$OS,$STEPS" in
    Linux,*lazy-update-depexts*)
      (set -x; sudo apt-get update)
      STEPS="${STEPS//lazy-update-depexts/}"
      ;;
    macOS,*lazy-update-depexts*)
      (set -x; brew update)
      STEPS="${STEPS//lazy-update-depexts/}"
      ;;
  esac
}

install-gpatch() {
  case "$OS" in
    macOS)
      lazy-update-depexts
      (set -x; brew install gpatch)
      PATH="$(brew --prefix gpatch)/libexec/gnubin:$PATH"
      printf '%s/libexec/gnubin\n' "$(brew --prefix gpatch)" >> "$GITHUB_PATH"
      (set -x; patch --version)
      ;;
  esac
}

install-depexts() {
  DEPEXTS="$(cd "$SETUPDUNEDIR" >/dev/null && dune show depexts 2>&1)" || \
    abort "got \"$DEPEXTS\" when listing depexts"
  case "$OS,$DEPEXTS" in
    *,) # No depexts to install
      ;;
    Linux,*)
      lazy-update-depexts
      (set -x; sudo apt-get install -y $DEPEXTS)
      ;;
    macOS,*)
      lazy-update-depexts
      (set -x; brew install $DEPEXTS)
      ;;
  esac
}

build() {
  (set -x; cd "$SETUPDUNEDIR" && dune build)
}

runtest() {
  (set -x; cd "$SETUPDUNEDIR" && dune runtest)
}

expand_steps() {
  case "$SETUPDUNESTEPS" in
    "")
      case "$SETUPDUNEAUTOMAGIC,$OS" in
        true,macOS)
          STEPS="install-dune lock lazy-update-depexts install-gpatch install-depexts build runtest"
          ;;
        true,*)
          STEPS="install-dune lock lazy-update-depexts install-depexts build runtest"
          ;;
        *)
          STEPS="install-dune"
          ;;
      esac
      ;;
    *)
      STEPS="$SETUPDUNESTEPS"
      ;;
  esac
}

w() {
  # Wrap a step to control whether it should run
  case "$STEPS" in
    *"$2"*)
      echo "::group::$1"
      "$2"
      echo "::endgroup::"
      ;;
  esac
}

main() {
  expand_steps
  w "Install dune" install-dune
  w "Lock the project dependencies" lock
  w "Install GNU patch on macOS" install-gpatch
  w "Install the external dependencies" install-depexts
  w "Build the project" build
  w "Run the test" runtest
}

main
