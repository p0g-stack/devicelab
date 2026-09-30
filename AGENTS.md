# devicelab: working agreements

Extends `~/.agents/AGENTS.md`. Seed; refine per directory as the nest fills in.

- Closest to the real platform wins. Say which substitute a run used and what
  it cannot show.
- An observation names the platform, host build and date, or it is not kept.
- Observations are append-only; a re-run adds one.
- Nothing here gates another repo's CI. Embedders copy observations into
  their own test fakes.
- Real devices: deny by default; only the known-good command list runs.
