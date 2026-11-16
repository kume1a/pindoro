# FSRS weight fit

`fit.py` fits FSRS-6 weights to a player's own review log with py-fsrs's optimizer (pinned in the
`justfile` recipe), as docs/learning/SPEC.md §12 plans once there are about 1 000 reviews.

```sh
just fsrs-fit ~/Downloads/pindoro-review-log.csv
```

It runs once, in Docker (`python:3.12-slim`, CPU-only PyTorch), never in CI, and needs no Python on
the machine. The input is the CSV from Settings → Export review log; the output is one line of
JSON, `{"weights": [21 numbers], "reviews": n, "cards": n}`. Paste it into Learning settings →
Memory model on the phone; the app uses the weights from its next launch. With fewer than 512
reviews py-fsrs returns the default weights unchanged.
