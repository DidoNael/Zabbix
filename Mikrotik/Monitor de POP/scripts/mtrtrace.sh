#!/bin/bash
TARGET=$1
[ -z "$TARGET" ] && echo "ERROR: empty target" && exit 1
mtr -r -c5 -w -n "$TARGET"
