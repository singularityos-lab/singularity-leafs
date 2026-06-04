# Contributing to singularity-leafs

## Development setup

```bash
git clone https://github.com/singularityos-lab/singularity-leafs
cd singularity-leafs
meson setup build
ninja -C build
```

To enable GObject Introspection:

```bash
meson setup build -Dintrospection=true
ninja -C build
```

## Code style

- Language: **Vala** or **C/C++** only.
- Indentation: **4 spaces** no tabs, no trailing whitespace.
- Keep files focused: one primary class per `.vala` file, named after the class
  (e.g. `LeafPane` -> `leaf_pane.vala`). Redundant suffixes in the
  filename (like `_manager`) should be avoided.

## License

By contributing you agree your code will be released under [GPL-3.0-only](LICENSE).

## Commit messages

Commits follow Conventional Commits:

```
<type>: <subject>
```

`<type>` is one of `feat`, `fix`, `chore`, `docs`, `build`, `ci`, `refactor`, `perf`, `style`, `test`, `revert`. Keep `<subject>` short, lowercase and in English. An optional scope is allowed: `<type>(<scope>): <subject>`.

When a commit closes an issue, use `<type>[closes #ID]: <issue title>`, for example:

```
fix[closes #2]: Discord doesn't open on Singularity desktop
```

Do not add co-author or attribution trailers.
