extends RefCounted
## Every implemented mechanic must have an entry, physical fixture and repeatable
## check here. Keep this registry aligned with docs/vault/Systems/Dev-Room.md.
const STATIONS: Array[Dictionary] = [
	{"id": "movement", "title": "01 · Movement & clearance", "at": Vector3(-8, 0, 0),
		"help": "WASD walk, Shift sprint, Space dash. Test slopes, braking, corners and the 4 cm crawl gap. F2 changes body size."},
	{"id": "food", "title": "02 · Food, relay & return homes", "at": Vector3(-8, 0, 10),
		"help": "E collects one snack; Q drops; R throws; RMB previews. Bring food to West home (-13,10) or East home (22,30) and stop to unload. Both share the quota; the compass finds the nearest. Homes stay away from food. F3 arms a two-second partner catch; press again to return its snack."},
	{"id": "climbing", "title": "03 · Climbing & cargo", "at": Vector3(4, 0, 10),
		"help": "C uses green routes; WASD crawls on surfaces. At the dish station 5 m south, climb then enter the left bowl: B at its open drain travels to the outside pipe (8,19); B there returns. Carry one food, block the exit, or try as human/ghost. F3 sends the real bug partner through and back. F4 ghost, F2 human, F5 reset."},
	{"id": "cart", "title": "04 · Cart & moving cargo", "at": Vector3(4.05, 0, 0),
		"help": "G at the caster/handle rolls the cart. Block its path, or use the north test ramp to board with cargo. F3 asks the real partner to roll it while you ride; F5 returns both to the north dock."},
	{"id": "stoves", "title": "05 · Flames, oil & cookware", "at": Vector3(16, 0, 0),
		"help": "H toggles gas from the floor/hand valve. C reaches the stove or fryer rim. Test lit/off burners, pot protection, oil, cargo release and ten-second ghosts."},
	{"id": "ovens", "title": "06 · Oven heat & doors", "at": Vector3(16, 0, 10),
		"help": "Human: J door, K heat. Bug: crawl through the closed vent; K at inside/outside shutoffs. Test gradual damage, door obstruction and safe escape."},
	{"id": "storage", "title": "07 · Storage & food spawning", "at": Vector3(-8, 0, 22),
		"help": "B opens/closes cabinets and box lids from either side. Walk inside, close up, then exit. Block a sweep with a body or stack. Ghosts cannot operate controls. Search inside for new foods. F3 depletes their supply to 3; wait 15 seconds for a random refill to 12. F5 resets. E picks up one food; Q drops; F squeezes fry grease. Pepper boosts speed and hurts; grape weaves; frozen food drops and freezes you after 15 seconds (3-second thaw). Kinetic hits drop food."},
	{"id": "vents", "title": "08 · Vents & cover", "at": Vector3(4, 0, 24),
		"help": "Crawl through the exposed production duct between all four mouths. Humans cannot fit. A separate solid cover wall tests shotgun cover. F2 switches roles."},
	{"id": "combat", "title": "09 · Weapons, ghost & rounds", "at": Vector3(16, 0, 22),
		"help": "Human: LMB shoots the real peer. At the cradle on the left, T swaps gas/shotgun and R reloads shells; hold LMB to spray. Leave gas docked to refill. F7 moves the target. Test cover, recoil and low-ceiling scooting. F4 ghost, F5 reset, F6 clock."},
]

static func titles() -> Array[String]:
	var result: Array[String] = []
	for station: Dictionary in STATIONS: result.append(station.title)
	return result
