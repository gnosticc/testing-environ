# StatusIconDisplay.gd
# A component that dynamically creates and arranges icons for all active
# status effects on its parent (a BaseEnemy). It positions itself based on a
# Marker2D named StatusIconAnchor on its parent.
# VERSION 1.2: Fixed inconsistent icon scaling by counteracting the parent
# enemy's scale to achieve a consistent on-screen size.

class_name StatusIconDisplay
extends Node2D

# --- Tunable Properties ---
@export var icon_size: float = 16.0
@export var icon_padding: float = 2.0

# --- Node References ---
var owner_enemy: BaseEnemy
var status_effect_component: StatusEffectComponent

# This function is called by BaseEnemy after it has initialized.
func initialize(p_owner: BaseEnemy):
	owner_enemy = p_owner
	status_effect_component = owner_enemy.status_effect_component
	
	# The most important step: connect to the signal that tells us when to update.
	if is_instance_valid(status_effect_component):
		status_effect_component.status_effects_changed.connect(_on_status_effects_changed)
		# Update once immediately to show any initial effects.
		_on_status_effects_changed(owner_enemy)

func _on_status_effects_changed(_owner_node: Node):
	# 1. Clear all existing icons.
	for child in get_children():
		child.queue_free()
		
	if not is_instance_valid(status_effect_component):
		return

	# 2. Create a list of icons and their data to display from the active effects.
	var effects_to_display: Array[Dictionary] = []
	for effect_key in status_effect_component.active_effects:
		var effect_entry = status_effect_component.active_effects[effect_key]
		if is_instance_valid(effect_entry.data) and is_instance_valid(effect_entry.data.icon):
			effects_to_display.append({
				"icon": effect_entry.data.icon,
				"scale_mult": effect_entry.data.visual_scale_multiplier
			})
			
	if effects_to_display.is_empty():
		return

	# 3. Create and arrange the new icon sprites.
	var total_width = (effects_to_display.size() * icon_size) + ((effects_to_display.size() - 1) * icon_padding)
	var current_x = -total_width / 2.0
	
	for effect_info in effects_to_display:
		var icon_texture: Texture2D = effect_info.icon
		var scale_multiplier: float = effect_info.scale_mult

		var icon_sprite = Sprite2D.new()
		icon_sprite.texture = icon_texture
		
		# --- SOLUTION: Counteract Parent Scale ---
		var texture_size = icon_texture.get_size()
		if texture_size.x > 0 and is_instance_valid(owner_enemy):
			# 1. Calculate the base scale to make the icon a consistent world size (e.g., 16px)
			var base_scale_factor = icon_size / texture_size.x
			
			# 2. Apply the specific multiplier from the StatusEffectData resource
			var final_desired_scale = base_scale_factor * scale_multiplier
			
			# 3. Counteract the owner's scale to achieve a consistent ON-SCREEN size.
			# We divide by the parent's scale to cancel out the inherited scaling.
			# We only need to use one axis since our scaling is uniform.
			if owner_enemy.scale.x != 0:
				icon_sprite.scale = Vector2.ONE * (final_desired_scale / owner_enemy.scale.x)
		# --- END SOLUTION ---
			
		icon_sprite.position.x = current_x + (icon_size / 2.0)
		# Position the icon so its anchor is at its bottom-center
		icon_sprite.position.y = -icon_size / 2.0
		
		add_child(icon_sprite)
		
		current_x += icon_size + icon_padding
