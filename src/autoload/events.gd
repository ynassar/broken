## Global signal bus. Systems talk through here so scenes stay decoupled.
extends Node

# Economy / channel
signal money_changed(new_amount: int)
signal subscribers_changed(new_count: int)
signal video_posted(result: Dictionary)

# Challenges
signal challenge_started(challenge: Dictionary)
signal challenge_finished(challenge: Dictionary, won: bool, stats: Dictionary)

# Hostiles
signal owner_became_hostile(owner_id: String)
signal hostile_defeated(owner_id: String, loot: int)
signal hostile_spotted_player(owner_id: String)
signal hostile_lost_player(owner_id: String)

# Player
signal player_health_changed(hp: float, max_hp: float)
signal player_died()
signal player_respawned(bill: int)
signal inventory_changed()

# UI
signal toast(text: String)
signal prompt_changed(text: String)
