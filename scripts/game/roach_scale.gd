extends RefCounted
## World units remain meter-like; the source art stays at its macro authoring size.
## Geometry/reach and locomotion deliberately use separate scales: tiny bodies
## need playable travel speeds across the diner rather than 40x longer rounds.
const GEOMETRY := 0.025
const MOVEMENT := 0.15
const CAMERA_DISTANCE := 0.22
const CAMERA_HEIGHT := 0.035
const CAMERA_NEAR := 0.001
const COLLISION_MARGIN := 0.00025
