extends Node3D
## Cosmetic rig. Observed replicated movement drives the pose on every peer.
## This node never reads gameplay input, moves a body, or publishes network state.

var motion_speed := 0.0
var shotgun_equipped := false
var shotgun_pitch := 0.0
var reload_blend := 0.0
var reload_cycle := 0.0
var recoil_phase := 0
var recoil_age := 0.0
var _was_recoiling := false
var _elapsed := 0.0
var _cycle := 0.0
var _speed := 0.0
@onready var body: Node3D = $BodyRoot
@onready var head: Node3D = $BodyRoot/Head
@onready var arm_left: Node3D = $BodyRoot/ArmLeft
@onready var arm_right: Node3D = $BodyRoot/ArmRight
@onready var leg_left: Node3D = $LegLeft
@onready var leg_right: Node3D = $LegRight

func _process(delta: float) -> void:
	if delta <= 0.0 or not is_visible_in_tree():
		return
	_elapsed += delta
	if recoil_phase!=0:
		_pose_recoil()
		_was_recoiling=true
		return
	if _was_recoiling:
		position=Vector3.ZERO
		rotation.x=0
		rotation.z=0
		arm_left.rotation.z=-0.10
		arm_right.rotation.z=0.10
		leg_left.rotation.z=0
		leg_right.rotation.z=0
		_was_recoiling=false
	_speed = lerpf(_speed, clampf(motion_speed, 0.0, 6.0), 1.0-exp(-10.0*delta))
	var moving := smoothstep(0.015,0.45,_speed)
	var pace := lerpf(0.8,2.0,clampf(_speed/5.5,0,1))
	_cycle += delta * TAU * pace * moving
	var bob := absf(sin(_cycle)) * 0.014 * moving
	var drop := -0.03 + bob
	body.position.y = drop + sin(_elapsed*2.1)*0.0014*(1.0-moving)
	body.rotation.z = sin(_cycle)*0.014*moving
	body.rotation.x = moving*0.025
	head.rotation.y = sin(_elapsed*0.57)*0.035*(1.0-moving)
	head.rotation.x = sin(_elapsed*1.1)*0.006
	var swing := 0.31*moving
	# The character faces -Z and the limbs extend down -Y. Positive X rotation
	# bends the elbows forward; flex increases on the forward arm swing.
	arm_left.rotation.x = sin(_cycle)*swing+0.055
	arm_right.rotation.x = -sin(_cycle)*swing+0.055
	(arm_left.get_node("Forearm") as Node3D).rotation.x = 0.17 + maxf(0,sin(_cycle))*0.18*moving
	(arm_right.get_node("Forearm") as Node3D).rotation.x = 0.17 + maxf(0,-sin(_cycle))*0.18*moving
	_pose_leg(leg_left,_cycle,moving,drop)
	_pose_leg(leg_right,_cycle+PI,moving,drop)
	if shotgun_equipped:
		_pose_holding_arm(arm_right,Vector3(0.13,1.34,-0.125),Vector3(0.48,1.22,0.03),1.0)
		_pose_holding_arm(arm_left,Vector3(0.095,1.37,-0.45),Vector3(-0.34,1.23,-0.10),-1.0)

func weapon_basis() -> Basis:
	return Basis(Vector3.RIGHT, shotgun_pitch).slerp(Basis(Vector3.RIGHT, 0.22) * Basis(Vector3.BACK, 0.65), reload_blend)

func _pose_holding_arm(upper: Node3D, target: Vector3, hint: Vector3, side: float) -> void:
	var grip := Vector3(0.13,1.40,-0.19)
	var aim_basis := weapon_basis()
	target=grip+aim_basis*(target-grip)
	if side < 0 and reload_blend > 0:
		# Reach to the belt, feed a shell into the receiver, then draw back.
		var feed := smoothstep(0.10, 0.72, reload_cycle) * (1.0 - smoothstep(0.86, 1.0, reload_cycle))
		var port := grip + aim_basis * Vector3(0, -0.065, -0.03)
		var hand_at := Vector3(-0.23, 1.06, -0.10).lerp(port, feed)
		target = target.lerp(hand_at, reload_blend)
	var offset := target-upper.position
	var distance := clampf(offset.length(),0.05,0.649)
	var axis := offset.normalized()
	var along := (0.33*0.33+distance*distance-0.32*0.32)/(2*distance)
	var bend := (hint-upper.position).slide(axis).normalized()
	var elbow_position := upper.position+axis*along+bend*sqrt(maxf(0,0.33*0.33-along*along))
	upper.basis=Basis(Quaternion(Vector3.DOWN,(elbow_position-upper.position).normalized()))
	var lower := upper.get_node("Forearm") as Node3D
	var lower_basis := Basis(Quaternion(Vector3.DOWN,(target-elbow_position).normalized()))
	lower.basis=upper.basis.inverse()*lower_basis
	var hand := lower.get_node("Hand") as Node3D
	hand.basis=lower_basis.inverse()*aim_basis*Basis(Vector3.UP,side*1.22)

func _pose_recoil() -> void:
	var recovery := smoothstep(0.0,0.90,recoil_age) if recoil_phase==3 else 0.0
	var fall := smoothstep(0.0,0.26,recoil_age) if recoil_phase==1 else 1.0
	var pitch := PI*0.5*fall*(1-recovery)
	var flail := exp(-recoil_age*2.2) if recoil_phase==1 else 0.0
	rotation.x=pitch
	rotation.z=sin(recoil_age*13)*0.12*flail
	var center_height := lerpf(1.02,0.26,fall)*(1-recovery)+1.02*recovery
	var local_spin := Basis(Vector3.RIGHT,pitch)*Basis(Vector3.BACK,rotation.z)
	position=Basis(Vector3.UP,rotation.y)*(Vector3(0,center_height,0)-local_spin*Vector3(0,1.02,0))
	body.position.y=-sin(recovery*PI)*0.18
	body.rotation=Vector3(0,0,0)
	head.rotation.x=-0.16*(1-recovery)
	for side: float in [-1.0,1.0]:
		var arm := arm_left if side<0 else arm_right
		arm.rotation=Vector3(0.25+sin(recoil_age*16+side)*0.8*flail,0,side*lerpf(0.55,0.20,recovery))
		(arm.get_node("Forearm") as Node3D).rotation=Vector3(0.45+0.35*flail,0,0)
		(arm.get_node("Forearm/Hand") as Node3D).rotation=Vector3(0.06,side*1.22,-side*0.04)
		var leg := leg_left if side<0 else leg_right
		leg.position.y=1.02
		leg.rotation=Vector3(0.20*(1-recovery)+sin(recoil_age*12+side)*0.45*flail+sin(recovery*PI)*0.65,0,side*0.10*(1-recovery))
		var shin := leg.get_node("Shin") as Node3D
		shin.rotation.x=-0.35*(1-recovery)-sin(recovery*PI)*1.1
		(shin.get_node("Foot") as Node3D).rotation.x=0.12*(1-recovery)
	if recoil_phase==3:
		# Plant the soles as the knees tuck under the body. This remains a visual
		# offset relative to the player's floor, never movement or a physics query.
		var lowest := INF
		for leg: Node3D in [leg_left,leg_right]:
			var foot := leg.get_node("Shin/Foot") as Node3D
			var relative: Transform3D=get_parent().global_transform.affine_inverse()*foot.global_transform
			for z: float in [-0.17,0.10]:
				lowest=minf(lowest,(relative*Vector3(0,-0.17,z)).y)
		position.y-=lowest*smoothstep(0,0.3,recovery)
		for side: float in [-1.0,1.0]:
			var arm := arm_left if side<0 else arm_right
			var lower := arm.get_node("Forearm") as Node3D
			var hand := lower.get_node("Hand") as Node3D
			var old_arm := arm.basis
			var old_lower := lower.basis
			var old_hand := hand.basis
			var target := Vector3(0.13,1.34,-0.125) if side>0 else Vector3(0.095,1.37,-0.45)
			var hint := Vector3(0.48,1.22,0.03) if side>0 else Vector3(-0.34,1.23,-0.10)
			_pose_holding_arm(arm,target,hint,side)
			var blend := smoothstep(0.45,1.0,recovery)
			arm.basis=old_arm.slerp(arm.basis,blend)
			lower.basis=old_lower.slerp(lower.basis,blend)
			hand.basis=old_hand.slerp(hand.basis,blend)

func _pose_leg(thigh: Node3D, phase: float, amount: float, drop: float) -> void:
	# Local ground-plane IK keeps the thick soles planted in the art rest pose.
	# This is presentation, not world-space foot locking or terrain locomotion.
	thigh.position.y = 1.02 + drop
	var lift := maxf(0.0,sin(phase)) * 0.09 * amount
	var forward := cos(phase) * 0.20 * amount
	var target := Vector2(0.17+lift-thigh.position.y,forward)
	var length := clampf(target.length(),0.1,0.849)
	var upper := 0.45
	var lower := 0.40
	var heading := atan2(-target.y,-target.x)
	var hip_angle := heading + acos(clampf((upper*upper+length*length-lower*lower)/(2.0*upper*length),-1,1))
	var knee_angle := -acos(clampf((length*length-upper*upper-lower*lower)/(2.0*upper*lower),-1,1))
	thigh.rotation.x = hip_angle
	var shin := thigh.get_node("Shin") as Node3D
	shin.rotation.x = knee_angle
	(shin.get_node("Foot") as Node3D).rotation.x = -hip_angle-knee_angle
