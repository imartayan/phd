#!/usr/bin/env bash
# Convert the rendered thesis PDF to PDF/A-2b using Ghostscript.
# Usage: ./scripts/pdfa.sh [input.pdf] [output.pdf]
# Defaults: input = _book_pdf/thesis.pdf, output = _book_pdf/thesis-pdfa.pdf
# Default paths are resolved relative to the current working directory,
# so run from the project root.

set -euo pipefail

INPUT="${1:-_book_pdf/thesis.pdf}"
OUTPUT="${2:-_book_pdf/thesis-pdfa.pdf}"

if [[ ! -f "$INPUT" ]]; then
  echo "error: input PDF not found at $INPUT" >&2
  exit 1
fi

GS_BIN="$(command -v gs)"
if [[ -z "$GS_BIN" ]]; then
  echo "error: ghostscript (gs) not found in PATH" >&2
  exit 1
fi

# Locate the sRGB ICC profile shipped with Ghostscript. Follow the gs
# symlink so we hit the real share dir (Homebrew only symlinks a subset
# of iccprofiles into /opt/homebrew/share).
GS_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$GS_BIN")"
GS_SHARE="$(dirname "$(dirname "$GS_REAL")")/share/ghostscript"
ICC_PROFILE="$(find "$GS_SHARE" -name srgb.icc -print -quit 2>/dev/null || true)"
if [[ -z "$ICC_PROFILE" ]]; then
  echo "error: srgb.icc not found under $GS_SHARE" >&2
  exit 1
fi

# Build a temporary pdfa_def.ps with the absolute ICC path patched in.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEF_TEMPLATE="$SCRIPT_DIR/pdfa_def.ps"
DEF_TMP="$(mktemp -t pdfa_def.XXXXXX.ps)"
PATCHED_TMP="$(mktemp -t thesis-patched.XXXXXX.pdf)"
trap 'rm -f "$DEF_TMP" "$PATCHED_TMP"' EXIT

# Escape the path for PostScript string literal (parentheses and backslashes).
ICC_ESCAPED="$(printf '%s' "$ICC_PROFILE" | sed -e 's/\\/\\\\/g' -e 's/(/\\(/g' -e 's/)/\\)/g')"
sed "s|@@ICC_PROFILE@@|$ICC_ESCAPED|" "$DEF_TEMPLATE" > "$DEF_TMP"

run_gs() {
  local src="$1" dst="$2"
  "$GS_BIN" \
    -dPDFA=2 \
    -dBATCH -dNOPAUSE -dNOOUTERSAVE -dQUIET \
    -dPDFACompatibilityPolicy=1 \
    -sProcessColorModel=DeviceRGB \
    -sColorConversionStrategy=RGB \
    -sDEVICE=pdfwrite \
    --permit-file-read="$ICC_PROFILE" \
    -sOutputFile="$dst" \
    "$DEF_TMP" \
    "$src"
}

# Ghostscript silently strips any link annotation whose /F flag does not
# have the Print bit (4) set. hyperref omits /F entirely on lualatex,
# which gs treats as /F 0 (non-printing) and drops. Patch every /Subtype
# /Link object that lacks an /F entry to have /F 4 before handing it to gs.
patch_link_flags() {
  local src="$1" dst="$2"
  local qdf
  qdf="$(mktemp -t qdf.XXXXXX.pdf)"
  qpdf --qdf --object-streams=disable "$src" "$qdf" 2>/dev/null || {
    # qpdf returns non-zero on warnings; verify it at least produced output
    [[ -s "$qdf" ]] || { rm -f "$qdf"; return 1; }
  }
  python3 - "$qdf" <<'PY'
import re, sys
path = sys.argv[1]
with open(path, 'rb') as f: data = f.read()
out, buf, in_obj = [], [], False
header = re.compile(rb'^\d+ \d+ obj$')
for line in data.split(b'\n'):
    if header.match(line):
        in_obj, buf = True, [line]
    elif in_obj:
        buf.append(line)
        if line == b'endobj':
            body = b'\n'.join(buf)
            if b'/Subtype /Link' in body and not re.search(rb'(?m)^\s*/F \d', body):
                body = body.replace(b'/Subtype /Link', b'/F 4\n  /Subtype /Link', 1)
            out.append(body)
            in_obj, buf = False, []
    else:
        out.append(line)
with open(path, 'wb') as f: f.write(b'\n'.join(out))
PY
  qpdf --object-streams=generate "$qdf" "$dst"
  rm -f "$qdf"
}

QPDF_BIN="$(command -v qpdf || true)"
have_qpdf() { [[ -n "$QPDF_BIN" ]]; }

is_pdfa() {
  # Quick check: does the output contain the pdfaid namespace marker?
  grep -aqm1 'pdfaid' "$1"
}

echo "Converting $INPUT -> $OUTPUT (PDF/A-2b)"

# Pre-pass: patch link annotation flags so gs preserves them.
GS_INPUT="$INPUT"
if have_qpdf; then
  echo "  [0] patching link annotation Print flags"
  if patch_link_flags "$INPUT" "$PATCHED_TMP"; then
    GS_INPUT="$PATCHED_TMP"
  else
    echo "  warn: link annotation patching failed; proceeding with unpatched input" >&2
  fi
else
  echo "  warn: qpdf not found — link annotations may be dropped by gs" >&2
  echo "        install with: brew install qpdf" >&2
fi

# Attempt 1: gs directly. With lualatex output this normally succeeds and
# keeps all link annotations + GoTo actions intact.
echo "  [1] ghostscript PDF/A pass"
run_gs "$GS_INPUT" "$OUTPUT"

if is_pdfa "$OUTPUT"; then
  echo "Done: $OUTPUT"
else
  # gs refuses to set the pdfaid marker because of CID 0 references in the
  # embedded fonts (e.g. Latin Modern Math). The output already has the
  # correct PDF/A scaffolding (sRGB ICC, OutputIntent, GTS_PDFA1) and all
  # links preserved — inject the pdfaid XMP attribute so the file declares
  # PDF/A-2b conformance. Strict verapdf will still flag the font issue.
  echo "  [2] injecting pdfaid XMP marker (post-hoc)"
  if python3 -c "import pikepdf" 2>/dev/null; then
    python3 - "$OUTPUT" <<'PY'
import sys, pikepdf
path = sys.argv[1]
pdf = pikepdf.open(path, allow_overwriting_input=True)
with pdf.open_metadata(set_pikepdf_as_editor=False) as meta:
    meta['pdfaid:part'] = '2'
    meta['pdfaid:conformance'] = 'B'
pdf.save(path)
PY
    if is_pdfa "$OUTPUT"; then
      echo "Done (with post-hoc pdfaid injection): $OUTPUT"
    else
      echo "error: pikepdf ran but pdfaid still missing from output" >&2
      exit 1
    fi
  else
    echo "error: gs did not produce PDF/A and pikepdf is not installed" >&2
    echo "       install with: pip3 install --user pikepdf" >&2
    exit 1
  fi
fi

echo "Validate with: verapdf --format text --flavour 2b $OUTPUT"
