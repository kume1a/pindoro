# v1 screens (PLACEHOLDER)

> Placeholder written during Milestone 0 bootstrap; replace with the real screen specs.
> In M0 every screen is a placeholder built from `pindoro_design` widgets.

| Route         | Screen     | Purpose                                                                  |
| ------------- | ---------- | ------------------------------------------------------------------------ |
| `/welcome`    | Welcome    | First run only. Logo plate "პინდორო", one-line pitch, "start" button.    |
| `/city`       | City       | Pick a city (M0: Tbilisi only, from the bundled fixture / catalog).      |
| `/area`       | Area       | Pick the whole city or a district / neighbourhood.                       |
| `/difficulty` | Difficulty | easy / medium / hard / expert, with a one-line explanation each.         |
| `/home`       | Home       | Level + XP progress, current area and difficulty, "play" button.         |
| `/quiz`       | Quiz       | `StreetPlate` on top, unlabelled map, tap to drop a pin, confirm.        |
| `/results`    | Results    | Round summary: per-question `FeedbackBadge`, points, XP, level progress. |
| `/settings`   | Settings   | Theme, language, about / OSM attribution and licences.                   |

Flow: first run `/welcome → /city → /area → /difficulty → /home`; later launches open `/home`.
A round is 10 questions (`QuestionSelector`), then `/results`.

Quiz feedback after confirm: yellow truth street, cobalt "you" pin, ink dashed measure line with the
distance in metres (tabular figures), tier badge.
