#!/bin/sh
# Three timed 100 mm slides to measure the active stage's real DPI.
cd "$(dirname "$0")/.."
for i in 1 2 3; do
    printf '\nRun %s of 3: put the mouse at the 0 mark, press Enter, then slowly slide it along a straight edge and stop exactly on 100 mm (6 s).' "$i"
    read -r _
    .build/debug/x3ctl measure 6 100
done
