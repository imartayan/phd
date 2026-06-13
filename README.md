# Algorithm design and implementation for the scale of sequencing data

This repository contains all the sources of my [PhD thesis](https://phd.martayan.org/).

It can generate both an HTML and a PDF version thanks to [Quarto](https://quarto.org/).

## Requirements

- [Install Quarto](https://quarto.org/docs/get-started/)
- Python dependencies: `python -m pip install -r requirements.txt`
- TeX Live dependencies: `tlmgr install dvisvgm pgf standalone`

For the PDF version:
- A working LuaLaTeX environment
- [IBM Plex Sans](https://www.fontsquirrel.com/fonts/ibm-plex) and [DejaVu Sans Mono](https://www.fontsquirrel.com/fonts/dejavu-sans-mono) fonts

## Compilation

### Live HTML preview

```sh
quarto preview
```

This will generate a live HTML preview that is automatically updated when you modify the sources.

### PDF version

```sh
quarto render -t pdf --output-dir _book_pdf
```

This will generate the PDF version of the thesis in `_book_pdf/thesis.pdf` (with LaTeX sources in `thesis.tex` if you need them).
