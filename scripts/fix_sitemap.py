import os
import re
import sys
from pathlib import Path

out = Path(os.environ.get("QUARTO_PROJECT_OUTPUT_DIR", "_book"))
f = out / "sitemap.xml"

if not f.exists():  # PDF-only render: nothing to fix
    sys.exit(0)

xml = f.read_text()
xml = re.sub(r"/index\.html</loc>", "/</loc>", xml)
xml = re.sub(r"\.html</loc>", "</loc>", xml)
f.write_text(xml)
