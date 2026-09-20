## Persistent player state: money, channel, inventory, skills, hostiles, progress.
## Pure data + rules; no scene references. Saved to user://save.json.
extends Node

const SAVE_PATH := "user://save.json"
const STARTING_MONEY := 250
const STARTING_SUBS := 120

var money: int = STARTING_MONEY
var subscribers: int = STARTING_SUBS
var videos_posted: int = 0

## item_id -> count (consumables) or 1 (gear). Lost on death, except keep_on_death items.
var inventory: Dictionary = {}
## skill_id -> level. Never lost.
var skills: Dictionary = {}
## Equipped utensil item id ("" = bare hands).
var utensil: String = ""
## Equipped weapon item id ("" = fists).
var weapon: String = ""

## challenge_id -> {"won": bool, "broll": bool, "time": float}
var completed: Dictionary = {}
## owner ids currently hunting the player (challenge ids double as owner ids).
var hostiles: Array = []
## owner_id -> bonus health multiplier (1.5 if B-roll succeeded)
var owner_health_mult: Dictionary = {}

var current_region: String = "us_west"
var current_city: String = "los_angeles"

var profanity_enabled: bool = true

func _ready() -> void:
	load_game()

# ---------------------------------------------------------------- money / subs

func add_money(amount: int) -> void:
	money = max(0, money + amount)
	Events.money_changed.emit(money)

func can_afford(amount: int) -> bool:
	return money >= amount

func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	add_money(-amount)
	return true

func add_subscribers(amount: int) -> void:
	subscribers = max(0, subscribers + amount)
	Events.subscribers_changed.emit(subscribers)

# ---------------------------------------------------------------- inventory

func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))

func has_item(item_id: String) -> bool:
	return item_count(item_id) > 0

func add_item(item_id: String, count: int = 1) -> void:
	inventory[item_id] = item_count(item_id) + count
	Events.inventory_changed.emit()

func consume_item(item_id: String) -> bool:
	if not has_item(item_id):
		return false
	inventory[item_id] -= 1
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	Events.inventory_changed.emit()
	return true

func buy_item(item_id: String) -> bool:
	var def: Dictionary = Data.items.get(item_id, {})
	if def.is_empty():
		return false
	var price := int(def.get("price", 0))
	if def.get("kind", "") == "gear" and has_item(item_id):
		return false
	if not spend(price):
		return false
	add_item(item_id, 1)
	if def.get("slot", "") == "utensil":
		utensil = item_id
	elif def.get("slot", "") == "weapon":
		weapon = item_id
	return true

func buy_skill(skill_id: String) -> bool:
	var def: Dictionary = Data.skills.get(skill_id, {})
	if def.is_empty():
		return false
	var level := skill_level(skill_id)
	var max_level := int(def.get("max_level", 5))
	if level >= max_level:
		return false
	var price := int(def.get("base_price", 100)) * (level + 1)
	if not spend(price):
		return false
	skills[skill_id] = level + 1
	Events.inventory_changed.emit()
	return true

func skill_level(skill_id: String) -> int:
	return int(skills.get(skill_id, 0))

func skill_price(skill_id: String) -> int:
	var def: Dictionary = Data.skills.get(skill_id, {})
	return int(def.get("base_price", 100)) * (skill_level(skill_id) + 1)

## Eating modifiers derived from skills + equipped gear (consumed by EatingSim).
func eating_profile() -> Dictionary:
	var pickup_mult := 1.0 - 0.10 * skill_level("quick_hands")      # faster pickup
	var chew_mult := 1.0 + 0.15 * skill_level("iron_jaw")           # faster chewing
	var capacity_mult := 1.0 + 0.08 * skill_level("big_stomach")    # more capacity
	var charisma := skill_level("charisma")
	var utensil_def: Dictionary = Data.items.get(utensil, {})
	return {
		"pickup_time_mult": maxf(0.4, pickup_mult),
		"chew_rate_mult": chew_mult,
		"capacity_mult": capacity_mult,
		"broll_bonus": 0.08 * charisma,
		"utensil": utensil_def,
		"has_sweatpants": has_item("sweatpants"),
	}

## Video production quality multiplier from gear (1.0 = phone camera).
func production_quality() -> float:
	var q := 1.0
	for id in inventory.keys():
		var def: Dictionary = Data.items.get(id, {})
		if def.get("kind", "") == "gear" and def.has("quality_bonus"):
			q += float(def["quality_bonus"])
	return q

# ---------------------------------------------------------------- challenges / hostiles

func record_challenge(challenge_id: String, won: bool, broll: bool, time_used: float) -> void:
	completed[challenge_id] = {"won": won, "broll": broll, "time": time_used}
	if won and not hostiles.has(challenge_id):
		hostiles.append(challenge_id)
		if broll:
			owner_health_mult[challenge_id] = 1.5
		Events.owner_became_hostile.emit(challenge_id)

func is_completed(challenge_id: String) -> bool:
	return completed.has(challenge_id) and completed[challenge_id]["won"]

func hostile_health_mult(owner_id: String) -> float:
	return float(owner_health_mult.get(owner_id, 1.0))

# ---------------------------------------------------------------- death

## Applies death penalties: pay hospital bill, lose inventory (except keep_on_death gear).
func apply_death(hospital_bill: int) -> void:
	var kept := {}
	for id in inventory.keys():
		var def: Dictionary = Data.items.get(id, {})
		if def.get("keep_on_death", false):
			kept[id] = inventory[id]
	inventory = kept
	if not has_item(utensil):
		utensil = ""
	if not has_item(weapon):
		weapon = ""
	add_money(-hospital_bill)
	Events.inventory_changed.emit()
	Events.player_respawned.emit(hospital_bill)

# ---------------------------------------------------------------- save / load

func to_dict() -> Dictionary:
	return {
		"money": money, "subscribers": subscribers, "videos_posted": videos_posted,
		"inventory": inventory, "skills": skills, "utensil": utensil, "weapon": weapon,
		"completed": completed, "hostiles": hostiles, "owner_health_mult": owner_health_mult,
		"current_region": current_region, "current_city": current_city,
		"profanity_enabled": profanity_enabled,
	}

func from_dict(d: Dictionary) -> void:
	money = int(d.get("money", STARTING_MONEY))
	subscribers = int(d.get("subscribers", STARTING_SUBS))
	videos_posted = int(d.get("videos_posted", 0))
	inventory = d.get("inventory", {})
	skills = d.get("skills", {})
	utensil = d.get("utensil", "")
	weapon = d.get("weapon", "")
	completed = d.get("completed", {})
	hostiles = d.get("hostiles", [])
	owner_health_mult = d.get("owner_health_mult", {})
	current_region = d.get("current_region", "us_west")
	current_city = d.get("current_city", "los_angeles")
	profanity_enabled = bool(d.get("profanity_enabled", true))

func reset() -> void:
	from_dict({})

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), "\t"))
		f.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		from_dict(json.data)
	f.close()
