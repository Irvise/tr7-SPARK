#!/bin/sh
# Build the verified core and the REPL with the Alire toolchain.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

cd "$root/tr7"
alr exec -- gprbuild -P tr7.gpr -j"${JOBS:-4}"

cd "$root/tr7i"
alr exec -- gprbuild -P tr7i.gpr -j"${JOBS:-4}"

echo "build: ok -> tr7i/bin/tr7i"
