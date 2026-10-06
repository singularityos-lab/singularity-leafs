# singularity-leafs

> [!IMPORTANT]
> Report bugs and request features in the
> [Singularity Desktop tracker](https://github.com/singularityos-lab/singularity-desktop/issues/new/choose).

A terminal emulator for the [Singularity Desktop Environment](https://github.com/singularityos-lab).

## Command cheatsheet

View, Command Cheatsheet (Ctrl+Shift+H) opens a searchable panel with common commands and the keyboard shortcuts of Leafs and of the command line. Click a command, or press Enter on the first result, to type it into the terminal without running it; words in italics are placeholders to replace.

### For distributors

The bundled list in `data/cheatsheet/commands.md` is written for Leafs. More pages in the same format are read from `singularity-leafs/cheatsheet/`, `tldr/pages/common/` and `tldr/pages/linux/` in each data directory (`XDG_DATA_HOME` and `XDG_DATA_DIRS`). Packaging [tldr-pages](https://github.com/tldr-pages/tldr) at `/usr/share/tldr/pages` adds them with no other change; the panel then shows the CC BY 4.0 attribution the licence requires. See [data/cheatsheet/NOTICE](data/cheatsheet/NOTICE).

## Requirements

- [Meson](https://mesonbuild.com/) ≥ 1.0
- [Vala](https://vala.dev/) compiler
- [Vetro](https://github.com/singularityos-lab/vetro/) compiler
- GTK4
- libgee-0.8
- VTE for GTK4 (`vte-2.91-gtk4`)
- json-glib-1.0
- [libsingularity](https://github.com/singularityos-lab/libsingularity)

## Build & Install

```sh
meson setup build
meson compile -C build
meson install -C build
```

## License

GPL-3.0-only - see [LICENSE](LICENSE).

## Use of Generative AI

Maintainers may use generative AI tools as assistants while working on singularity-leafs. Non-trivial assisted commits disclose the tool, model, and scope of the work.

AI tools may assist with code comments, documentation, repetitive code, and issue triage. Maintainers make project decisions and review every assisted change before it is merged.

Use these trailers for non-trivial assisted commits:

```plain
Assisted-by: <tool>:<model-version>
AI-Scope: <what the tool generated and the prompt or a short prompt summary>
```

Single-line completions, renames, and formatting changes do not need trailers.

Coding agents must also follow [AGENTS.md](AGENTS.md) before changing files,
creating commits, or opening pull requests.
