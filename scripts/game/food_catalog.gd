extends RefCounted
## Shared, immutable food tuning. Values are pantry servings, not item counts.

const RoachScale := preload("res://scripts/game/roach_scale.gd")
const STACK_LIMIT := 1
const FOODS: Array[Dictionary] = [
	{"name": "Sugar cube", "short": "SUGAR", "value": 1, "weight": 1.0, "wobble": 0.6, "radius": 0.25, "height": 0.48, "bounce": 0.18, "color": Color(0.92, 0.87, 0.72)},
	{"name": "Runaway pea", "short": "PEA", "value": 2, "weight": 1.0, "wobble": 1.0, "radius": 0.32, "height": 0.62, "bounce": 0.58, "color": Color(0.34, 0.54, 0.12)},
	{"name": "Cheese wedge", "short": "CHEESE", "value": 3, "weight": 3.0, "wobble": 0.85, "radius": 0.28, "height": 0.56, "bounce": 0.12, "color": Color(0.94, 0.57, 0.11)},
	{"name": "Forbidden doughnut", "short": "DOUGHNUT", "value": 4, "weight": 2.5, "wobble": 1.6, "radius": 0.24, "height": 0.45, "bounce": 0.30, "color": Color(0.64, 0.22, 0.25)},
]

static func info(kind: int) -> Dictionary:
	var food := FOODS[clampi(kind, 0, FOODS.size() - 1)].duplicate()
	food["radius"] = float(food["radius"]) * RoachScale.GEOMETRY
	food["height"] = float(food["height"]) * RoachScale.GEOMETRY
	return food

static func speed_scale(weight: float) -> float:
	return 1.0 / (1.0 + maxf(weight, 0.0) * 0.10)
