#!/bin/sh
# Prepare one branch, or verify both branches with --release.
# This command never has a force mode: missing or stale evidence is a refusal.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
usage() {
    echo "usage: prepare_release.sh <version> <2.0|2.1> [--archive FILE] [--candidate SHA]" >&2
    echo "       prepare_release.sh --release [--version VERSION] --archive-dir DIR" >&2
    exit 2
}

if [ "$#" -eq 0 ]; then
    usage
fi

MODE=single
VERSION=
BRANCH=
ARCHIVE=
ARCHIVE_DIR=
CANDIDATE=${RRC_CANDIDATE_SHA:-$(git -C "$ROOT" rev-parse HEAD)}
MATRIX=
EVIDENCE_ROOT=
GOLDEN_ROOT=

if [ "$1" = "--release" ]; then
    MODE=release
    shift
    while [ "$#" -gt 0 ]; do
        case $1 in
            --version) [ "$#" -ge 2 ] || usage; VERSION=$2; shift 2 ;;
            --archive-dir) [ "$#" -ge 2 ] || usage; ARCHIVE_DIR=$2; shift 2 ;;
            --candidate|--candidate-sha) [ "$#" -ge 2 ] || usage; CANDIDATE=$2; shift 2 ;;
            --matrix) [ "$#" -ge 2 ] || usage; MATRIX=$2; shift 2 ;;
            --evidence-root) [ "$#" -ge 2 ] || usage; EVIDENCE_ROOT=$2; shift 2 ;;
            --golden-root) [ "$#" -ge 2 ] || usage; GOLDEN_ROOT=$2; shift 2 ;;
            *) usage ;;
        esac
    done
    if [ -z "$VERSION" ]; then
        VERSION=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$ROOT/info.json")
    fi
else
    [ "$#" -ge 2 ] || usage
    VERSION=$1
    BRANCH=$2
    shift 2
    case $BRANCH in 2.0|2.1) ;; *) echo "release refused: missing branch: expected 2.0 or 2.1" >&2; exit 2 ;; esac
    while [ "$#" -gt 0 ]; do
        case $1 in
            --archive) [ "$#" -ge 2 ] || usage; ARCHIVE=$2; shift 2 ;;
            --candidate|--candidate-sha) [ "$#" -ge 2 ] || usage; CANDIDATE=$2; shift 2 ;;
            --matrix) [ "$#" -ge 2 ] || usage; MATRIX=$2; shift 2 ;;
            --evidence-root) [ "$#" -ge 2 ] || usage; EVIDENCE_ROOT=$2; shift 2 ;;
            --golden-root) [ "$#" -ge 2 ] || usage; GOLDEN_ROOT=$2; shift 2 ;;
            *) usage ;;
        esac
    done
fi

run_golden() {
    golden_branch=$1
    if ! (cd "$ROOT" && sh tests/golden/run --branch "$golden_branch"); then
        echo "release refused: golden corpus failed for branch $golden_branch" >&2
        exit 2
    fi
}

if [ "$MODE" = single ]; then
    if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
        echo "release refused: promotion requires an existing archive" >&2
        exit 2
    fi
    run_golden "$BRANCH"
    set -- "$ROOT/tools/release_gate.py" "$BRANCH" --candidate "$CANDIDATE" \
        --archive "$ARCHIVE" --version "$VERSION"
else
    if [ -z "$ARCHIVE_DIR" ] || [ ! -d "$ARCHIVE_DIR" ]; then
        echo "release refused: promotion requires an existing archive directory" >&2
        exit 2
    fi
    for release_branch in 2.0 2.1; do
        run_golden "$release_branch"
    done
    set -- "$ROOT/tools/release_gate.py" --release --candidate "$CANDIDATE" \
        --archive-dir "$ARCHIVE_DIR" --version "$VERSION"
fi

[ -n "$MATRIX" ] && set -- "$@" --matrix "$MATRIX"
[ -n "$EVIDENCE_ROOT" ] && set -- "$@" --evidence-root "$EVIDENCE_ROOT"
[ -n "$GOLDEN_ROOT" ] && set -- "$@" --golden-root "$GOLDEN_ROOT"
cd "$ROOT"
python3 "$@"
echo "release verdict: verified"
