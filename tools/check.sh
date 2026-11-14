#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

luac5.1 -p borjes-magasin/*.lua
for suite in test sync performance settings realm surnames diagnostics selftest xp; do
  lua5.1 "tests/$suite.lua"
done
for scenario in preloaded late failed combat; do
  lua5.1 tests/bootstrap.lua "$scenario"
done
python3 -m unittest discover -s tests -p 'test_package.py' -v
