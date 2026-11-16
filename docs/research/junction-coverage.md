# Junction coverage (Tbilisi, 2026-11-16)

The pipeline's junction-item step (`apps/pipeline/src/routes.ts`, SPEC §6.6) on the Geofabrik
extract of 2026-11-16: 20 000 origin–destination pairs drawn by street length, each driven by the
shortest legal route on the directed, turn-restricted graph (4 928 one-way edges of 22 491, 879
turn restrictions, 4 261 connector edges). A decision is a junction on a route with another legal
way on, U-turns aside.

| Measure                         | Count   | Share            |
| ------------------------------- | ------- | ---------------- |
| Origin–destination pairs routed | 20000   | 100.0 % of 20000 |
| Decisions driven                | 1484744 |                  |
| Distinct decisions              | 26737   |                  |
| Junction items chosen           | 6424    | covers 90.0 %    |
| … bridge                        | 34      | 0.5 %            |
| … district                      | 5118    | 79.7 %           |
| … gateway_in                    | 235     | 3.7 %            |
| … gateway_out                   | 217     | 3.4 %            |
| … skeleton                      | 820     | 12.8 %           |
| Items with a landmark           | 1484    | 23.1 %           |

Answers SPEC §15's first open question: a route drives about 74 decisions, so 90 % coverage takes
6 400 items, not the ~450 skeleton decisions §3 estimated; 820 of them are skeleton turns. They
open gradually (§16.14), at most 10 new a day. 18 bridges over the Mtkvari were found; 2 944
landmark candidates (monuments 882, pharmacies 621, banks 268, fuel 262, …).
