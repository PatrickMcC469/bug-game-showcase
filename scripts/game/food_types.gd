extends RefCounted
## Stable IDs for the new food system. Legacy FoodRun integer kinds are kept
## separate until its spawning and carrying replacement is ready.
const IDS: Array[StringName] = [&"spicy_pepper", &"fermented_fruit", &"frozen_food", &"french_fry"]
const Definition := preload("res://scripts/game/food_definition.gd")

static func definition(id: StringName) -> Resource:
	if id not in IDS: return null
	var resource := load("res://assets/food/" + str(id) + ".tres")
	# Callers can tune a private copy without changing another food's profile.
	return resource.duplicate() if resource is Definition else null

static func model(id: StringName) -> Node3D:
	var food := definition(id)
	return food.model_scene.instantiate() as Node3D if food != null else null
