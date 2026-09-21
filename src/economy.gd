## Static economy formulas. Everything money/subscriber related lives here so it can be tuned and tested.
class_name Economy
extends RefCounted

const RPM := 6.0                    # dollars per 1000 views (game-tuned, not real YouTube)
const SUB_RATE := 0.03              # subs gained per view (before quality)
const VIRAL_CHANCE := 0.07
const VIRAL_MULT := 8.0
const BROLL_MULT := 1.3
const BROLL_BASE_CHANCE := 0.35

## Views for a challenge video.
static func base_views(subscribers: int, weight_lbs: float, quality: float, won: bool, broll: bool) -> float:
	var difficulty := 0.6 + 0.12 * weight_lbs          # 2 lb → 0.84, 10 lb → 1.8
	var v := (subscribers * 1.2 + 3000.0) * difficulty * quality
	v *= 1.0 if won else 0.4
	if broll:
		v *= BROLL_MULT
	return v

## Full video result. rng lets tests be deterministic.
static func video_result(challenge: Dictionary, won: bool, broll: bool, subscribers: int, quality: float, rng: RandomNumberGenerator) -> Dictionary:
	var weight := float(challenge.get("total_weight_lbs", 2.0))
	var views := base_views(subscribers, weight, quality, won, broll)
	var viral := false
	if won and rng.randf() < VIRAL_CHANCE:
		viral = true
		views *= VIRAL_MULT
	var money := int(round(views / 1000.0 * RPM))
	var subs := int(round(views * SUB_RATE * quality))
	var prize := int(challenge.get("cash_prize", 0)) if won else 0
	var meal_cost := 0 if won else int(challenge.get("meal_price_usd", 0))
	return {
		"views": int(views), "money": money, "subs": subs, "viral": viral,
		"prize": prize, "meal_cost": meal_cost, "broll": broll, "won": won,
		"net_money": money + prize - meal_cost,
	}

static func broll_chance(charisma_bonus: float) -> float:
	return clampf(BROLL_BASE_CHANCE + charisma_bonus, 0.05, 0.95)

## Loot dropped by a defeated hostile.
static func hostile_loot(health_mult: float, rng: RandomNumberGenerator) -> int:
	return int(round((12.0 + rng.randf_range(0.0, 8.0)) * health_mult))

static func hospital_bill(region: Dictionary) -> int:
	return int(region.get("hospital_bill", 150))

## Uber fare by straight-line distance in metres.
static func uber_fare(distance_m: float) -> int:
	return int(ceil(4.0 + distance_m * 0.02))

static func uber_cancel_fee() -> int:
	return 5
