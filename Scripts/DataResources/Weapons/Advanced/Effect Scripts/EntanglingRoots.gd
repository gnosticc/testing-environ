# --- Path: res://Scripts/Weapons/Advanced/Effects/EntanglingRoots.gd ---
class_name EntanglingRoots
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _affected_enemies: Array[Node2D] = []

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	
	var radius = float(p_stats.get(&"root_pool_radius", 60.0))
	var desired_width = radius * 2
	
	# This variable will hold the final visual size of the sprite after scaling.
	var final_sprite_size = Vector2.ZERO

	# --- Sprite Scaling ---
	# First, calculate the sprite's scale to maintain its aspect ratio.
	var sprite_texture = animated_sprite.sprite_frames.get_frame_texture("active", 0)
	if is_instance_valid(sprite_texture):
		var texture_size = sprite_texture.get_size() # Get the full Vector2 size of the texture
		if texture_size.x > 0:
			var scale_factor = desired_width / texture_size.x
			animated_sprite.scale = Vector2.ONE * scale_factor
			# Calculate the final visual size of the sprite for the collision shape to use.
			final_sprite_size = texture_size * animated_sprite.scale

	# --- Collision Shape Sizing ---
	if collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = radius
	elif collision_shape.shape is RectangleShape2D:
		# FIX: Instead of creating a square, set the collision shape's size
		# to match the final visual dimensions of the scaled sprite.
		# This ensures the collision area has the same aspect ratio as the visuals.
		(collision_shape.shape as RectangleShape2D).size = final_sprite_size

	lifetime_timer.wait_time = float(p_stats.get(&"root_pool_duration", 5.0))
	lifetime_timer.start()
	animated_sprite.play("active")

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
		var root_status_duration = 3.0 + float(_specific_stats.get(&"root_status_duration_add", 0.0))
		var root_status = load("res://DataResources/StatusEffects/rooted_status.tres") as StatusEffectData
		if is_instance_valid(root_status):
			body.status_effect_component.apply_effect(root_status, _owner_player_stats.get_parent(), {}, root_status_duration, -1.0, &"rooted")
		
		if _specific_stats.get(&"roots_are_poisonous", false) and not _affected_enemies.has(body):
			_affected_enemies.append(body)
			var toxic_soil_status = load("res://DataResources/StatusEffects/toxic_soil_dot.tres") as StatusEffectData
			if is_instance_valid(toxic_soil_status):
				# Calculate the base damage of the censer's swing to use as the DoT's base damage.
				var swing_damage_percent = float(_specific_stats.get(&"swing_damage_percentage", 1.0))
				var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
				var base_damage = _owner_player_stats.get_calculated_base_damage(swing_damage_percent)
				var base_damage_as_potency = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)				
				# Apply the status effect, passing the calculated damage as the potency_override.
				body.status_effect_component.apply_effect(toxic_soil_status, _owner_player_stats.get_parent(), _specific_stats, -1.0, base_damage_as_potency)
	
	elif body is PlayerCharacter and _specific_stats.get(&"roots_are_healing", false):
		var heal_buff = load("res://DataResources/StatusEffects/nourishment_regen_buff.tres") as StatusEffectData
		if is_instance_valid(heal_buff):
			body.status_effect_component.apply_effect(heal_buff, body, {}, -1.0, -1.0, &"nourishment_buff")

func _on_body_exited(body: Node2D):
	if body is PlayerCharacter and _specific_stats.get(&"roots_are_healing", false):
		body.status_effect_component.remove_effect_by_unique_id(&"nourishment_buff")
