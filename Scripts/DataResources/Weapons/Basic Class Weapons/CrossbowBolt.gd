# crossbowbolt.gd
# This script controls the behavior of a single crossbow bolt projectile.
# It receives its properties from WeaponManager and deals damage based on player stats.
# It now fully integrates with the standardized stat system.
#
# UPDATED: Changed base class from Area2D to CharacterBody2D for proper physics movement.
# UPDATED: Movement now uses velocity and move_and_slide().
# UPDATED: Passes weapon tags to PlayerStats.get_calculated_player_damage for tag-specific damage modifiers.
# UPDATED: Integrates GLOBAL_PROJECTILE_PIERCE_COUNT_ADD for additional piercing.
# UPDATED: Integrates GLOBAL_PROJECTILE_MAX_RANGE_ADD for projectile lifetime.
# UPDATED: Integrates GLOBAL_LIFESTEAL_PERCENT for healing.
# UPDATED: Integrates GLOBAL_STATUS_EFFECT_CHANCE_ADD for status effect application.

extends CharacterBody2D # CHANGED: Now extends CharacterBody2D

# These variables will be set by _apply_all_stats_effects based on _received_stats.
var final_damage_amount: int
var final_speed: float
var final_applied_scale: Vector2
var direction: Vector2 = Vector2.RIGHT # Default value, will be overridden by set_attack_properties

var max_pierce_count: int
var current_pierce_count: int = 0 # Tracks how many enemies this projectile has pierced through

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite # Use $ shorthand
@onready var lifetime_timer: Timer = $LifetimeTimer # Use $ shorthand
@onready var collision_shape: CollisionShape2D = $CollisionShape2D # Use $ shorthand
@onready var damage_area: Area2D = $DamageArea # ADDED: Need an Area2D child for collision detection

var _stats_have_been_set: bool = false # Flag to ensure stats are applied once
var _received_stats: Dictionary = {} # Dictionary of weapon-specific stats passed from WeaponManager
var _owner_player_stats: PlayerStats # Reference to the player's PlayerStats node

func _ready():
	if not is_instance_valid(lifetime_timer):
		push_error("ERROR (CrossbowBolt): LifetimeTimer missing! Queueing free."); call_deferred("queue_free"); return
	else:
		# Connect lifetime timer to free the projectile after its duration.
		if not lifetime_timer.is_connected("timeout", Callable(self, "queue_free")):
			lifetime_timer.timeout.connect(self.queue_free)

	# ADDED: Connect signals for the Area2D child
	if not is_instance_valid(damage_area):
		push_error("ERROR (CrossbowBolt): DamageArea child node missing! Collisions will not be detected."); return
	else:
		if not damage_area.is_connected("body_entered", Callable(self, "_on_body_entered")):
			damage_area.body_entered.connect(self._on_body_entered)
		if not damage_area.is_connected("area_entered", Callable(self, "_on_area_entered")): # For other projectiles/areas
			damage_area.area_entered.connect(self._on_area_entered)
	
	# If stats were set via `set_attack_properties` before _ready() (e.g., call_deferred), apply them now.
	if _stats_have_been_set:
		_apply_all_stats_effects()


# Standardized initialization function called by WeaponManager when the attack is spawned.
# p_direction: The normalized direction vector for the projectile.
# p_attack_stats: Dictionary of specific stats for this weapon instance (from WeaponManager).
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(p_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	# Set direction, ensuring it's normalized or defaults to RIGHT.
	direction = p_direction.normalized() if p_direction.length_squared() > 0 else Vector2.RIGHT
	_received_stats = p_attack_stats.duplicate(true) # Deep copy to avoid modifying original
	_owner_player_stats = p_player_stats
	_stats_have_been_set = true
	
	# Set the projectile's rotation based on its direction.
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	
	# Apply all calculated stats and effects. Defer if not yet in tree.
	if is_inside_tree():
		_apply_all_stats_effects()
	else:
		call_deferred("_apply_all_stats_effects")


# Applies all calculated stats and effects to the projectile instance.
func _apply_all_stats_effects():
	if not _stats_have_been_set or not is_instance_valid(_owner_player_stats):
		push_warning("CrossbowBolt: Stats not set or owner_player_stats invalid. Cannot apply effects."); return

	# --- Damage Calculation (Data-Driven) ---
	# Retrieve weapon-specific damage percentage from received stats.
	var weapon_damage_percent = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 1.0))
	# Retrieve weapon tags to pass to the damage calculation.
	var weapon_tags: Array[StringName] = _received_stats.get(&"tags", [])
	# Calculate the final damage using the player's overall damage formula, including tags.
	var calculated_damage_float = _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags)
	final_damage_amount = int(round(maxf(1.0, calculated_damage_float))) # Ensure minimum 1 damage.

	# --- Projectile Speed Calculation ---
	# Retrieve base projectile speed from received stats.
	var base_projectile_speed = _received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SPEED], 220.0) # Default to 220.0 from blueprint
	var player_projectile_speed_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	final_speed = base_projectile_speed * player_projectile_speed_multiplier
	
	# DEBUG: Print values for projectile speed calculation
	print("CrossbowBolt DEBUG: base_projectile_speed from _received_stats: ", base_projectile_speed)
	print("CrossbowBolt DEBUG: player_projectile_speed_multiplier from PlayerStats: ", player_projectile_speed_multiplier)
	print("CrossbowBolt DEBUG: Calculated final_speed: ", final_speed)

	# --- Pierce Count ---
	var base_pierce_count = _received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PIERCE_COUNT], 0)
	# Apply global projectile pierce count addition.
	var global_pierce_add = int(_owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_PIERCE_COUNT_ADD))
	max_pierce_count = base_pierce_count + global_pierce_add

	# --- Scale Calculation (Visual and Collision) ---
	var base_scale_x = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_X], 1.0))
	var base_scale_y = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_Y], 1.0))
	var player_projectile_size_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	final_applied_scale.x = base_scale_x * player_projectile_size_multiplier
	final_applied_scale.y = base_scale_y * player_projectile_size_multiplier
	
	_apply_visual_scale() # Apply the calculated scale to sprite and collision shape
	
	# --- Lifetime Calculation ---
	var base_lifetime = float(_received_stats.get(&"base_lifetime", 2.0))
	var effect_duration_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	# Apply global projectile max range addition to lifetime for ranged projectiles.
	var global_max_range_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_MAX_RANGE_ADD)
	if final_speed > 0:
		base_lifetime += (global_max_range_add / final_speed) * 0.5 # Example tuning factor

	lifetime_timer.wait_time = base_lifetime * effect_duration_multiplier
	
	if is_instance_valid(lifetime_timer) and lifetime_timer.is_stopped():
		lifetime_timer.start()


# Applies the calculated visual scale to the AnimatedSprite2D and CollisionShape2D.
func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_scale
	else: push_warning("WARNING (CrossbowBolt): AnimatedSprite2D is invalid, cannot apply visual scale.")
	
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale
	else: push_warning("WARNING (CrossbowBolt): CollisionShape2D is invalid, cannot apply collision scale.")


# --- Physics Process for Movement ---
func _physics_process(delta: float):
	velocity = direction * final_speed # Set the velocity
	move_and_slide() # Perform the movement and collision response

# --- Collision Detection for Area2D Child ---
# Note: Since this node is now a CharacterBody2D, body_entered on its *own* collision
# will result in a physics slide/response. For detection, use an Area2D child.
func _on_body_entered(body: Node2D):
	# This function is called by the DamageArea child's body_entered signal.
	_handle_hit(body)

func _on_area_entered(area: Area2D):
	# This function is called by the DamageArea child's area_entered signal.
	# Useful if you expect projectiles to hit other Areas (e.g., player's Area2D, other projectiles)
	pass # Implement if needed

func _handle_hit(body: Node2D):
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		var enemy_target = body as BaseEnemy
		if not is_instance_valid(enemy_target) or enemy_target.is_dead(): return

		var owner_player = _owner_player_stats.get_parent() if is_instance_valid(_owner_player_stats) else null
		
		# Prepare attack stats to pass to the enemy's take_damage method.
		# This includes armor penetration from the player's stats.
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}
		
		enemy_target.take_damage(final_damage_amount, owner_player, attack_stats_for_enemy)
		
		# --- Apply Lifesteal ---
		var global_lifesteal_percent = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
		if global_lifesteal_percent > 0:
			var heal_amount = final_damage_amount * global_lifesteal_percent
			if is_instance_valid(owner_player) and owner_player.has_method("heal"):
				owner_player.heal(heal_amount)

		# --- Apply Status Effects on Hit ---
		if _received_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy_target.status_effect_component):
			var status_apps: Array = _received_stats.get(&"on_hit_status_applications", [])
			var global_status_effect_chance_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)

			for app_data_res in status_apps:
				var app_data = app_data_res as StatusEffectApplicationData
				if is_instance_valid(app_data):
					var final_application_chance = app_data.application_chance + global_status_effect_chance_add
					final_application_chance = clampf(final_application_chance, 0.0, 1.0)
					
					if randf() < final_application_chance:
						enemy_target.status_effect_component.apply_effect(
							load(app_data.status_effect_resource_path) as StatusEffectData,
							owner_player, # Source of the effect (the player).
							_received_stats, # Pass weapon stats for scaling of the status effect.
							app_data.duration_override,
							app_data.potency_override
						)
						# print("CrossbowBolt: Applied status from '", app_data.status_effect_resource_path, "' to enemy.") # Debug print.

		# --- Handle Pierce Count ---
		current_pierce_count += 1
		if current_pierce_count > max_pierce_count:
			# --- Handle Projectile Explode on Death ---
			var global_explode_chance = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_PROJECTILE_EXPLODE_ON_DEATH_CHANCE)
			if randf() < global_explode_chance:
				_spawn_explosion_effect() # This function needs to be implemented or defined in a base projectile class.
			
			# --- Handle Projectile Bounce (if not pierced) ---
			var global_bounce_add = int(_owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_PROJECTILE_BOUNCE_COUNT_ADD))
			if global_bounce_add > 0:
				# This logic would need to store the bounce count in the projectile and handle redirection.
				# For simplicity now, we'll just queue_free unless you want to implement bounce logic.
				# A real bounce would decrement a bounce counter and change direction.
				# For now, it will simply queue_free after pierce limit.
				pass # Placeholder for bounce logic
			
			call_deferred("queue_free") # Projectile consumed all pierces, queue for removal.

	# If the projectile hits a world obstacle, destroy it.
	elif body.is_in_group("world_obstacles"):
		# --- Handle Projectile Bounce (if hitting obstacle) ---
		var global_bounce_add = int(_owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_PROJECTILE_BOUNCE_COUNT_ADD))
		if global_bounce_add > 0:
			# This logic would need to store the bounce count in the projectile and handle redirection.
			# For now, it will simply queue_free.
			pass # Placeholder for bounce logic
		
		# --- Handle Projectile Explode on Death ---
		var global_explode_chance = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_PROJECTILE_EXPLODE_ON_DEATH_CHANCE)
		if randf() < global_explode_chance:
			_spawn_explosion_effect() # This function needs to be implemented or defined in a base projectile class.
		
		call_deferred("queue_free")

# Placeholder for explosion effect. You would implement this to spawn an Area2D with damage/visuals.
func _spawn_explosion_effect():
	# Example:
	# var explosion_scene = load("res://Scenes/Effects/Explosion.tscn")
	# if is_instance_valid(explosion_scene):
	#     var explosion_instance = explosion_scene.instantiate()
	#     get_tree().current_scene.add_child(explosion_instance)
	#     explosion_instance.global_position = self.global_position
	#     # Pass damage or scale if needed for the explosion
	push_warning("CrossbowBolt: _spawn_explosion_effect called. Implement your explosion scene here.")
