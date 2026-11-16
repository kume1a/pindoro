"""Golden FSRS-6 vectors for pindoro_learning (docs/learning/SPEC.md §4, §14).

Runs once in Docker via `just fsrs-vectors`, never in CI. Prints the JSON to stdout.
"""

import json
import sys
from datetime import datetime, timedelta, timezone
from importlib.metadata import version

from fsrs import Card, Rating, Scheduler, State

RETENTION = 0.9
MAX_INTERVAL = 365
T0 = datetime(2026, 1, 5, 9, 0, tzinfo=timezone.utc)

scheduler = Scheduler(
    desired_retention=RETENTION,
    learning_steps=(),
    relearning_steps=(),
    maximum_interval=MAX_INTERVAL,
    enable_fuzzing=False,
)


def on_due(prev_at, due):
    return due


def late(delta):
    return lambda prev_at, due: due + delta


def after(delta):
    return lambda prev_at, due: prev_at + delta


def early(fraction):
    return lambda prev_at, due: prev_at + (due - prev_at) * fraction


# Each review is (rating, when); `when` places it relative to the previous review and its due
# date, and is ignored for the first review (at T0).
SEQUENCES = {
    "good_on_time": [(3, None), (3, on_due), (3, on_due), (3, on_due)],
    "good_late_then_early": [
        (3, None),
        (3, late(timedelta(days=4, hours=5))),
        (3, early(0.5)),
        (3, on_due),
    ],
    "lapse": [(3, None), (1, on_due), (3, on_due), (3, on_due)],
    "lapse_after_late_review": [
        (3, None),
        (3, late(timedelta(days=10))),
        (1, on_due),
        (3, on_due),
    ],
    "again_same_day": [(1, None), (1, after(timedelta(minutes=10))), (3, on_due)],
    "easy": [(4, None), (4, on_due)],
    "hard_then_same_day_good": [(2, None), (3, after(timedelta(minutes=20))), (3, on_due)],
    "retrieval_1_and_2": [(3, None), (3, after(timedelta(minutes=15))), (3, on_due)],
    "relearn_in_session": [
        (3, None),
        (1, on_due),
        (1, after(timedelta(minutes=8))),
        (3, after(timedelta(days=1))),
    ],
    "just_under_a_day_late": [(3, None), (3, late(timedelta(hours=23, minutes=59))), (3, on_due)],
    "easy_to_the_cap": [(4, None)] + [(4, on_due)] * 6,
}


def iso(at):
    return at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def run(reviews):
    card = Card()
    out = []
    for rating, when in reviews:
        at = T0 if card.last_review is None else when(card.last_review, card.due)
        elapsed = (at - card.last_review).days if card.last_review else None
        r_before = scheduler.get_card_retrievability(card, at) if card.last_review else None
        card, _ = scheduler.review_card(card, Rating(rating), at)
        out.append(
            {
                "at": iso(at),
                "rating": rating,
                "elapsed_days": elapsed,
                "retrievability": r_before,
                "stability": card.stability,
                "difficulty": card.difficulty,
                "interval_days": (card.due - at).days,
                "due": iso(card.due),
            }
        )
    return out


def retrievability_probes():
    probes = []
    for stability in (0.212, 2.3065, 10.0, 100.0):
        for days in (0, 1, 5, 30, 365):
            card = Card(state=State.Review, stability=stability, difficulty=5.0, last_review=T0, due=T0)
            r = scheduler.get_card_retrievability(card, T0 + timedelta(days=days))
            probes.append({"stability": stability, "elapsed_days": days, "retrievability": r})
    return probes


json.dump(
    {
        "generator": f"py-fsrs {version('fsrs')}, tools/fsrs-vectors/gen.py",
        "parameters": list(scheduler.parameters),
        "desired_retention": RETENTION,
        "maximum_interval": MAX_INTERVAL,
        "tolerance": 1e-4,
        "sequences": [{"name": name, "reviews": run(reviews)} for name, reviews in SEQUENCES.items()],
        "retrievability": retrievability_probes(),
    },
    sys.stdout,
    indent=2,
)
sys.stdout.write("\n")
