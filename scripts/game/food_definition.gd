extends Resource
## Food data consumed by host-owned possession and effects.
## Loading a definition never applies an effect to a player.
enum Effect { SPICY, TIPSY, COLD, GREASE }

@export_group("Identity")
@export var food_id: StringName
@export var display_name := ""
@export var model_scene: PackedScene
@export var effect: Effect = Effect.SPICY
@export_multiline var effect_description := ""

@export_group("Spicy — provisional carry tuning")
@export_range(1.0, 2.0, 0.05) var speed_multiplier := 1.25
@export_range(0.0, 20.0, 0.5) var damage_per_second := 2.0

@export_group("Tipsy — provisional carry tuning")
@export_range(0.0, 0.5, 0.01) var steering_wobble := 0.18
@export_range(0.5, 5.0, 0.1) var wobble_period_seconds := 1.8

@export_group("Cold — provisional carry tuning")
@export_range(1.0, 30.0, 0.5) var freeze_after_seconds := 15.0
@export_range(0.25, 5.0, 0.25) var freeze_duration_seconds := 3.0
@export_range(0.5, 10.0, 0.5) var thaw_seconds := 4.0

@export_group("Grease — provisional carry tuning")
@export_range(0.5, 5.0, 0.25) var slick_lifetime_seconds := 3.0
@export_range(0.25, 5.0, 0.25) var slick_interval_seconds := 1.5
@export_range(1, 4, 1) var max_live_slicks := 2
@export_range(0.25, 2.0, 0.05) var trip_duration_seconds := 0.65
@export_range(1.0, 5.0, 0.25) var trip_immunity_seconds := 2.0

func effect_settings() -> Dictionary:
	match effect:
		Effect.SPICY: return {"speed_multiplier": speed_multiplier, "damage_per_second": damage_per_second}
		Effect.TIPSY: return {"steering_wobble": steering_wobble, "wobble_period_seconds": wobble_period_seconds}
		Effect.COLD: return {"freeze_after_seconds": freeze_after_seconds, "freeze_duration_seconds": freeze_duration_seconds, "thaw_seconds": thaw_seconds}
		Effect.GREASE: return {"slick_lifetime_seconds": slick_lifetime_seconds, "slick_interval_seconds": slick_interval_seconds, "max_live_slicks": max_live_slicks, "trip_duration_seconds": trip_duration_seconds, "trip_immunity_seconds": trip_immunity_seconds}
	return {}

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if food_id.is_empty() or display_name.is_empty(): errors.append("Food identity is missing")
	if model_scene == null: errors.append("Food model is missing")
	if effect_description.is_empty(): errors.append("Effect description is missing")
	if effect not in Effect.values(): errors.append("Unknown food effect")
	for key: String in effect_settings():
		var value := float(effect_settings()[key])
		if not is_finite(value) or value <= 0: errors.append("Invalid effect setting: " + key)
	if effect == Effect.SPICY and speed_multiplier <= 1: errors.append("Spicy food must increase speed")
	if effect == Effect.GREASE and trip_immunity_seconds <= trip_duration_seconds: errors.append("Trip immunity must outlast the stumble")
	return errors
