# NexGenVideo Plugins

Loadable **format plugins** for NexGenVideo. A plugin teaches the app a new
production format (music video, trailer, explainer, …) without touching the app
binary. This folder is the marketplace: the catalog below lists the plugins that
ship today, and the community extends it by PR.

## What a plugin is

A NexGenVideo plugin is a **thin, format-specific package** that registers against
the engine contract. It carries only format behavior:

- a Python **pack** (`nexgen_pack_<name>/`) that registers phases, sanity checks,
  duration policy, and reference libraries against the bundled engine — discovered
  via the `nexgen.packs` entry-point group;
- (added later) its **Claude-Code workflow layer** — the phases/commands that drive
  the format end-to-end.

A plugin is **not** the engine and **not** generation:

- The **Generic Engine** (`engine/nexgen_engine`) is **bundled in the .app and
  always loaded** — the generic quality motor: project state, the Bible /
  consistency core, the sanity framework, render cost/budget. It is not a plugin
  and is never shipped inside one.
- **Generation is nexgen's own** — BYO-key providers (fal, Marble, …) exposed by
  the Swift host as MCP tools. Plugins call those tools through Claude; they never
  bundle a generator or an engine.

(Internally the Python module is still called a "pack" — that's the engine-contract
term. The user-facing distributable is a "plugin", and a plugin contains a pack.)

## Catalog

| Plugin | What it does |
|---|---|
| **musicvideo** | Structured AI music-video production (analysis → brief → treatment → storyboard → bible → shotlist → sanity → frames → render). |

## Install a plugin

1. Download the plugin folder (e.g. `plugins/musicvideo/`).
2. Copy it into the NexGenVideo plugins directory:
   `~/Library/Application Support/NexGenVideo/plugins/<name>/`.
3. Restart NexGenVideo. On next launch the app bootstraps the plugin into the
   engine venv (via `uv`) and its format phases appear in the workflow.

> An in-app **ZIP Import** (drop a `.zip`, no Finder spelunking) is planned.

## Contribute a plugin

Plugins live in this folder — adding one is a pull request:

1. Create `plugins/<your-plugin>/` containing a `nexgen_pack_<name>/` Python pack.
2. Add a `pyproject.toml` that declares the entry point so the engine discovers it:

   ```toml
   [project.entry-points."nexgen.packs"]
   <name> = "nexgen_pack_<name>:<Name>Pack"
   ```

3. Register only **format behavior** against the engine contract — phases, sanity
   checks, duration policy, libraries. Don't re-implement the engine, and don't call
   generators yourself; go through nexgen's MCP tools, driven by Claude.
4. Add a row to the **Catalog** table above.

See [`docs/PLUGIN_STANDARD.md`](../docs/PLUGIN_STANDARD.md) for the full contract,
and [`musicvideo/`](musicvideo) as the reference implementation.
