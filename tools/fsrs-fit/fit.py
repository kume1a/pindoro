"""Fits FSRS-6 weights to an exported Pindoro review log (docs/learning/SPEC.md §12).

Reads the CSV from Settings → Export review log (path in argv[1]) and prints JSON the Memory model
screen takes: {"weights": [21 numbers], "reviews": n, "cards": n}. Only answers that moved a
card count, as in the app's changesSchedule(): no guesses, logged Explore answers, logs-only
drills or failed placement pins.
"""

import csv
import json
import sys
from datetime import datetime

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
    logs = [
        ReviewLog(
            card_id=cards.setdefault(r["item_id"], len(cards) + 1),
            rating=Rating(int(r["rating"])),
            review_datetime=datetime.fromisoformat(r["ts"].replace("Z", "+00:00")),
            review_duration=int(r["rt_ms"]) if r["rt_ms"] else None,
        )
        for r in rows
    ]
    if len(logs) < ENOUGH:
        print(f"only {len(logs)} reviews; SPEC §12 waits for about {ENOUGH}", file=sys.stderr)
    weights = Optimizer(logs).compute_optimal_parameters()
    json.dump(
        {"weights": [round(w, 4) for w in weights], "reviews": len(logs), "cards": len(cards)},
        sys.stdout,
    )
    print()


if __name__ == "__main__":
    main()
