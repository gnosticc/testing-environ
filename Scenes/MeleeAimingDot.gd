# MeleeAimingDot.gd
# Attach this to the root Node2D of MeleeAimingDot.tscn
# This node will position itself on an oval around its parent (the player)
# based on the mouse direction, and also rotate to aim at the mouse.
extends Node2D

# Adjust these in the Inspector for the MeleeAimingDot node in player.tscn
@export var oval_radius_x: float = 20.0 # Horizontal radius of the oval path
@export var oval_radius_y: float = 15.0 # Vertical radius of the oval path

# Optional: Visual representation of the dot itself
@onready var dot_visual: Sprite2D = $DotVisual # Assuming a child Sprite2D named DotVisual

func _process(_delta: float):
	var parent = get_parent()
	if not is_instance_valid(parent):
		# print_debug("MeleeAimingDot: Parent is not valid.")
		return

	var parent_global_pos: Vector2 = parent.global_position
	var mouse_global_pos: Vector2 = get_global_mouse_position()

	var direction_to_mouse_from_parent = (mouse_global_pos - parent_global_pos)

	if direction_to_mouse_from_parent.length_squared() > 0.001: # Avoid issues if mouse is exactly on parent
		var angle_to_mouse = direction_to_mouse_from_parent.angle()

		# Calculate the dot's local position on the oval based on this angle
		var local_pos_on_oval = Vector2()
		local_pos_on_oval.x = oval_radius_x * cos(angle_to_mouse)
		local_pos_on_oval.y = oval_radius_y * sin(angle_to_mouse)
		
		self.position = local_pos_on_oval # Set local position relative to the parent (player)

		# Make the dot itself (or its visual) point towards the mouse.
		# The direction for the dot's rotation is from its *new global position* towards the mouse.
		var direction_from_dot_to_mouse = (mouse_global_pos - self.global_position)
		if direction_from_dot_to_mouse.length_squared() > 0.001:
			var rotation_angle = direction_from_dot_to_mouse.angle()
			if is_instance_valid(dot_visual):
				# Assuming dot_visual sprite is drawn facing RIGHT by default.
				# If it faces LEFT by default, use: rotation_angle - PI
				# If it faces UP by default, use: rotation_angle + PI / 2.0
				# If it faces DOWN by default, use: rotation_angle - PI / 2.0
				dot_visual.rotation = rotation_angle
			else:
				# If no specific visual, rotate the MeleeAimingDot node itself.
				# Assuming this node's "forward" is to the right.
				self.rotation = rotation_angle 
	# else:
		# print_debug("MeleeAimingDot: Mouse is too close to parent to determine direction.")


# This function will be called by player.gd to get the origin for melee attacks
func get_attack_origin_global_position() -> Vector2:
	return self.global_position

# This function can be called by player.gd to get the direction the dot is aiming
func get_aiming_direction() -> Vector2:
	# Returns a normalized vector representing the direction the dot is pointing.
	# This assumes the node (or its dot_visual) is rotated such that its local positive X-axis points towards the target.
	if is_instance_valid(dot_visual):
		return Vector2.RIGHT.rotated(dot_visual.global_rotation)
	else:
		return Vector2.RIGHT.rotated(self.global_rotation)
