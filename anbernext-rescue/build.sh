#!/bin/sh
# Builds the static aarch64 rescue shell and prints its size/type.
set -eu
cd "$(dirname "$0")"
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags "-s -w" -o rescue-shell .
ls -lh rescue-shell
file rescue-shell
