# belt-sanitizer

The in-game half of B.E.L.T., a Factorio 2.1 benchmarking CLI. The mod does nothing on its own:
it refuses to load unless the CLI has written its `job.lua`.

## Interface (version 2)

The interface version is `protocol.INTERFACE` and the major version in `info.json`. Both must
equal the CLI's. A breaking change bumps them on both sides.

**Job (CLI → mod).** The CLI writes `job.lua` into its copy of the mod before each run:

```lua
return [==[{"interface":2,"kind":"sanitize","ticks":3600,"items":["iron-plate"],"fluids":["water"]}]==]
```

A job with another `interface` makes the mod raise an error in its main chunk, so Factorio exits
non-zero with the message. The job kinds are:

| `kind` | Fields | Launch mode |
|---|---|---|
| `sanitize` | `ticks`, `items`, `fluids` | `--test-save`; the mod ends the run with `script.finish_test` |
| `stamp` | `name`, `blueprint`, `count`, `buffer_ticks`, `bot_count`, `module_replacement` (`{name, quality}`) | `--start-server` on a copy of the base save; the CLI sends `/quit` after the result, and the server saves |

**Messages (mod → CLI).** One JSON object per stdout line, each starting with `BELT-SANITIZER `:

| `type` | Fields | When |
|---|---|---|
| `hello` | `interface` | first, from the main chunk |
| `warning` | `text` | any time; the run continues |
| `error` | `message` | the job failed; the run ends |
| `sanitize_result` | `report` | after `ticks` ticks |
| `stamp_result` | `report` | after building and `buffer_ticks` ticks |

Empty lists are left out of reports, because `helpers.table_to_json` can't tell `[]` from `{}`.

## Stamping

- **Probe:** each copy is first placed as ghosts on a private lab surface, deleted afterwards, to learn where it lands. Drills need ore, so in the probe each drill is swapped for 1×1 anchors on its corner tiles, which keeps the blueprint's bounding box. The player's map never sees the probe, and no events fire.
- **Clearing:** its area is cleared of everything except characters, and water is landfilled.
- **Placeholder ore:** a blueprint places a drill only over ore it can mine without fluid, so
  every drill stands on a placeholder ore while it's built. The placeholder is then replaced by
  the marker's ore on the whole mining area (natural ore there is replaced too), or by none for
  unmarked drills, and each drill is told to look again (`update_connections`).
- **Build:** `build_blueprint{raise_built = true}`, then every ghost is revived with
  `raise_revive = true`. Revival runs in passes, because wagons need their rails first.
- **Item requests:** modules and other requests are inserted directly.

## Tests

```
lua5.4 tests/run.lua
```

This covers the pure modules (`stamp/markers.lua`, `stamp/layout.lua`). Behaviour inside the game
is tested from the CLI's repository against a real Factorio.
