#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <pdf|folder>" >&2
  exit 1
fi

input="$1"

convert_one() {
  local pdf="$1"
  local svg="${pdf%.pdf}.svg"
  if [[ ! -f "$svg" ]]; then
    echo "Converting: $pdf -> $svg"
    pdftocairo -svg "$pdf" "$svg"
  fi
}

if [[ -f "$input" ]]; then
  convert_one "$input"
elif [[ -d "$input" ]]; then
  while IFS= read -r -d '' pdf; do
    convert_one "$pdf"
  done < <(find "$input" -name "*.pdf" -print0)
else
  echo "Error: '$input' is not a file or directory" >&2
  exit 1
fi
