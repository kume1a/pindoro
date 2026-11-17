"""Fits FSRS-6 weights to an exported Pindoro review log (docs/learning/SPEC.md §12).

Reads the CSV from Settings → Export review log (path in argv[1]) and prints JSON the Memory model
screen takes: {"weights": [21 numbers], "reviews": n, "cards": n}. Only answers that moved a
card count, as in the app's changesSchedule(): no guesses, logged Explore answers, logs-only
drills or failed placement pins. A carried-over card's first Good, which has no row, is put back
before its first review, as memoryAt() does.
"""

import csv
import json
import sys
from datetime import datetime, timedelta

from fsrs import Optimizer, Rating, ReviewLog

NEVER_SCHEDULE = {"pretest", "exploreLog", "crossings", "bearing"}
PLACEMENT_PASSES = {"3", "4"}
ENOUGH = 1000


def changes_schedule(row: dict[str, str]) -> bool:
    if row["format"] in NEVER_SCHEDULE:
        return False
    return row["format"] != "placement" or row["rating"] in PLACEMENT_PASSES


def main() -> None:
    with open(sys.argv[1], newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if changes_schedule(r)]
    cards: dict[str, int] = {}
    logs: list[ReviewLog] = []
    for r in rows:
        first = r["item_id"] not in cards
        card_id = cards.setdefault(r["item_id"], len(cards) + 1)
        ts = datetime.fromisoformat(r["ts"].replace("Z", "+00:00"))
        if first and r["elapsed_days"]:
            # A carried-over card began as a Good with no row of its own (carriedOver()).
            carried = ts - timedelta(days=float(r["elapsed_days"]))
            logs.append(
                ReviewLog(
                    card_id=card_id,
                    rating=Rating.Good,
                    review_datetime=carried,
                    review_duration=None,
                )
            )
        logs.append(
            ReviewLog(
                card_id=card_id,
                rating=Rating(int(r["rating"])),
                review_datetime=ts,
                review_duration=int(r["rt_ms"]) if r["rt_ms"] else None,
            )
        )
    if len(rows) < ENOUGH:
        print(f"only {len(rows)} reviews; SPEC §12 waits for about {ENOUGH}", file=sys.stderr)
    weights = Optimizer(logs).compute_optimal_parameters()
    json.dump(
        {"weights": [round(w, 4) for w in weights], "reviews": len(rows), "cards": len(cards)},
        sys.stdout,
    )
    print()


if __name__ == "__main__":
    main()
