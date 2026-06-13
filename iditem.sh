#!/bin/bash
X=/home/joao/koliseuot/data/items/items.xml
for id in 49535 43968 60855; do
  echo "=== item $id ==="
  awk -v id="$id" '$0 ~ ("id=\""id"\"") {f=1} f{print} f && /<\/item>/ {exit}' "$X" | head -10
done
