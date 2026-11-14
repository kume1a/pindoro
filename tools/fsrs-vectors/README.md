# FSRS golden vectors

`gen.py` writes `shared/fixtures/fsrs_vectors.json` with py-fsrs (pinned in the `justfile` recipe),
the reference FSRS-6 implementation. `pindoro_learning`'s FSRS port must match it to 1e-4
(docs/learning/SPEC.md §4, §14).

```sh
just fsrs-vectors
```

It runs once, in Docker (`python:3.12-slim`), never in CI, and needs no Python on the machine.
Regenerate only when the FSRS version, the weights, the retention or the sequences change, and
commit the JSON together with the Dart change it proves.

Settings: SPEC §4 weights (py-fsrs defaults), retention 0.9, maximum interval 365 days, no learning
or relearning steps (in-session relearning is the planner's job), no fuzz.
