# Design decisions and tuning (living document)

## World scale
- Each region is split into cities; each city is a walkable grid about 5 minutes wide at walking speed (5 m/s → ~1.5 km). Regions: 5 cities each, 8 regions → 40 cities, 25 restaurants per city, 1,000 total.
- The demo city is a 3×3 block slice (~170 m square).

## Eating simulation (src/eating/eating_sim.gd)
- In-game clock runs 10× real time, so a "30 minute" challenge is 3 real minutes.
- Base stomach capacity: 2,000 g at calm pace fills the bar. Skills raise capacity; sweatpants/tums raise the max.
- Bite size depends on food type and utensil (bare hands: 45 g solid, 15 g noodles, 8 g soup).
- Pace multiplier: eating faster than 12 g/s over a 12 s window multiplies fullness gain (up to ×2.2).
- Pause: first 3 s of idle settle the bar at 1.6/s; longer idle bloats at 0.9/s.
- Vomit: starting a bite at max fullness, or chewing more than 3 points past max.

## Economy (src/economy.gd)
- Views = (subs × 1.2 + 3000) × difficulty(weight) × production quality; loss ×0.4; B-roll ×1.3; viral 7% ×8.
- Money = views × $6 / 1000; subs = views × 3% × quality.
- Losing pays the meal price. Death pays the region hospital bill and drops all items except `keep_on_death` ones.

## Hostiles
- Every owner you beat joins the hunter pool for good. All of them roam their city; owners from unlocked regions also spawn abroad. No cap on the pool; per-city active count is tuned per city size (target: up to the full 25 local owners + imports).
- Knocked-out owners come back after a cooldown (1 in-game day; 90 s in the demo).
- Detection: 24 m range, 150° FOV while roaming, any direction within 4 m, line-of-sight raycast. Evade: 6 s without LOS.

## Open questions for the owner
- randysantel.com / foodchallenges.com are blocked by the sandbox's network policy. The LA dataset came from search-engine snippets; the other 975 challenges need either the domain unblocked or a CSV export.
