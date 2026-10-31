extends RefCounted
## Offline collision repair for solid set dressing. Keep the original meshes,
## transforms and material batches; bake matching geometry on unscaled bodies.
const SOLID_PROPS := ["FallenTray", "ChoppingBoard", "KnifeBlade", "KnifeHandle",
	"Plate", "CleanPlate", "StandingPlate", "SqueezeBottle", "CoffeeMug",
	"StoolBase", "StoolPost", "StoolSeat", "RubberMat", "NapkinHolder",
	"ExtractorHood", "SinkWastePipe", "GooseneckTap", "AdjustableFoot",
	"PlasticThermos", "LongLifeFood", "RubberDuckToy"]

func apply(map: Node3D) -> void:
	for label: Node in map.find_children("*", "Label3D", true, false):
		# Packed truck art includes surface printing, owned by that asset.
		if "ExterminatorTruck" not in str(map.get_path_to(label)): label.free()
	for mesh: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.has_node("SurfaceCollision"): continue
		if not mesh.is_visible_in_tree() and not mesh.has_meta("atmosphere_batched"): continue
		var path := str(map.get_path_to(mesh))
		var selected := false
		for part: String in path.split("/"):
			for prefix: String in SOLID_PROPS:
				if part.begins_with(prefix): selected = true
		if not selected: continue
		var parent := mesh.get_parent()
		var solid := false
		while parent != null and parent != map:
			if parent is CollisionObject3D: solid = true
			parent = parent.get_parent()
		if solid: continue
		var body := StaticBody3D.new()
		body.name = "SurfaceCollision"
		mesh.add_child(body)
		body.owner = map
		body.add_to_group("diner_static", true)
		# Imported props can have scaled ancestors. Bake their full transform
		# into the vertices and keep the physics body's world basis unscaled.
		body.global_transform = Transform3D(Basis.IDENTITY, mesh.global_position)
		var faces := mesh.mesh.get_faces()
		var transform := body.global_transform.affine_inverse() * mesh.global_transform
		for i: int in faces.size(): faces[i] = transform * faces[i]
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var collision := CollisionShape3D.new()
		collision.name = "Shape"
		collision.shape = shape
		body.add_child(collision)
		collision.owner = map
