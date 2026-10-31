extends RefCounted
## Conversion from the original blockout coordinates to the compact diner.
## Geometry is baked offline; characters, cargo and camera are never scaled.
const SCALE := 0.45
const ROOM_SIZE := Vector2(16.2, 13.5)
const SITE_SIZE := Vector2(27, 35)
const PANTRY_HOME := Vector3(-10.8, 0, -4.5)
const WORKTOP_HEIGHT := 1.08
const CART_X := 4.05
const CART_NORTH := -1.35
const CART_SOUTH := 2.565

static func point(blockout_position: Vector3) -> Vector3:
	return blockout_position * SCALE
