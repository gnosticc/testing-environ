# SparkProjectile.gd
# Behavior for the Wizard's Spark projectile.
# A basic magical projectile that seeks a target.
#
# UPDATED: Changed base class from Area2D to CharacterBody2D for proper physics movement.
# UPDATED: Passes weapon tags to PlayerStats.get_calculated_player_damage for tag-specific damage modifiers.
# UPDATED: Integrates GLOBAL_LIFESTEAL_PERCENT for healing.
# UPDATED: Integrates GLOBAL_STATUS_EFFECT_CHANCE_ADD for status effect application.
# UPDATED: Integrates GLOBAL_PROJECTILE_MAX_RANGE_ADD for projectile lifetime.
# UPDATED: Uses PlayerStatKeys for all stat lookups.

extends CharacterBody2D # CHANGED: Now extends CharacterBody2D for physics movement

# These variables will be set by _apply_all_stats_effects
var final_damage_amount: int = 0
var final_speed: float = 0.0
var final_applied_scale: Vector2 = Vector2(1,1)
var direction: Vector2 = Vector2.RIGHT # Will be set by set_attack_properties

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer") as Timer
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D # Ensure this is the correct node name for your CollisionShape
@onready var damage_area: Area2D = $DamageArea # ADDED: Need an Area2D child for collision detection

var _stats_have_been_set: bool = false
var _received_stats: Dictionary = {} # This holds the calculated weapon stats from WeaponManager
var _owner_player_stats: PlayerStats # Reference to the player's PlayerStats node

func _ready():
	if not is_instance_valid(lifetime_timer):
		push_error("ERROR (SparkProjectile): LifetimeTimer missing! Queueing free."); call_deferred("queue_free"); return
	else:
		lifetime_timer.timeout.connect(Callable(self, "queue_free")) # Connect to queue_free directly

	if not is_instance_valid(collision_shape):
		push_error("ERROR (SparkProjectile): CollisionShape2D missing! Projectile will not collide.");
		call_deferred("queue_free"); return # Queue free if essential node is missing

	# ADDED: Connect signals for the Area2D child
	if not is_instance_valid(damage_area):
		push_error("ERROR (SparkProjectile): DamageArea child node missing! Collisions will not be detected."); return
	else:
		if not damage_area.is_connected("body_entered", Callable(self, "_on_body_entered")):
			damage_area.body_entered.connect(self._on_body_entered)
		if not damage_area.is_connected("area_entered", Callable(self, "_on_area_entered")):
			damage_area.area_entered.connect(self._on_area_entered)

	# If set_attack_properties was called before _ready (e.g., if instanced via add_child then set properties),
	# we can apply stats immediately. Otherwise, it will be called after _ready.
	if _stats_have_been_set:
		_apply_all_stats_effects()

func _physics_process(delta: float):
	velocity = direction * final_speed # Set the velocity
	move_and_slide() # Perform the movement and collision response

# Standardized initialization function called by WeaponManager.
# p_direction: The normalized direction vector for the projectile.
# p_attack_stats: Dictionary of specific stats for this weapon instance (already calculated by WeaponManager).
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(p_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	direction = p_direction.normalized() if p_direction.length_squared() > 0 else Vector2.RIGHT
	_received_stats = p_attack_stats.duplicate(true) # Deep copy
	_owner_player_stats = p_player_stats
	_stats_have_been_set = true
	
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	
	# Only apply stats if _ready has already run and this node is in the tree.
	# If _ready hasn't run yet, _apply_all_stats_effects will be called from _ready.
	if is_inside_tree():
		_apply_all_stats_effects()

func _apply_all_stats_effects():
	if not _stats_have_been_set or not is_instance_valid(_owner_player_stats):
		push_warning("SparkProjectile: Stats not set or owner_player_stats invalid. Cannot apply effects."); return

	# --- Damage Calculation leveraging unified method ---
	var weapon_damage_percent = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 1.2)) # Default to 1.2 (120%)
	var weapon_tags: Array[StringName] = _received_stats.get(&"tags", []) # Retrieve weapon tags
	var calculated_damage_float = _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags) # Pass tags
	final_damage_amount = int(round(maxf(1.0, calculated_damage_float))) # Ensure minimum 1 damage.
	
	# --- Speed Calculation ---
	var base_projectile_speed = _received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SPEED], 250.0)
	var player_projectile_speed_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	final_speed = base_projectile_speed * player_projectile_speed_multiplier
	
	# --- Scale Calculation ---
	var base_scale_x = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_X], 1.0))
	var base_scale_y = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_Y], 1.0))
	var player_projectile_size_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	final_applied_scale.x = base_scale_x * player_projectile_size_multiplier
	final_applied_scale.y = base_scale_y * player_projectile_size_multiplier
	
	_apply_visual_scale()
	
	# --- Lifetime Calculation ---
	var base_lifetime = float(_received_stats.get(&"base_lifetime", 1.5)) # Assuming base_lifetime is a direct key
	var effect_duration_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	# Apply global projectile max range addition to lifetime for ranged projectiles.
	var global_max_range_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_MAX_RANGE_ADD)
	if final_speed > 0:
		base_lifetime += (global_max_range_add / final_speed) * 0.5 # Example tuning factor

	lifetime_timer.wait_time = base_lifetime * effect_duration_multiplier
	
	# Ensure timer is started if it was already created by _ready() but not yet started
	if is_instance_valid(lifetime_timer) and lifetime_timer.is_stopped():
		lifetime_timer.start()

func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_scale
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale

# --- Collision Detection ---
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
	# The spark dissipates on the first thing it hits.
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		var enemy_target = body as BaseEnemy
		if not is_instance_valid(enemy_target) or enemy_target.is_dead(): return

		var owner_player_char = _owner_player_stats.get_parent() if is_instance_valid(_owner_player_stats) else null
		
		# Prepare attack stats to pass to the enemy's take_damage method.
		# This includes armor penetration from the player's stats.
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}

		enemy_target.take_damage(final_damage_amount, owner_player_char, attack_stats_for_enemy)
		
		# --- Apply Lifesteal ---
		var global_lifesteal_percent = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
		if global_lifesteal_percent > 0:
			var heal_amount = final_damage_amount * global_lifesteal_percent
			if is_instance_valid(owner_player_char) and owner_player_char.has_method("heal"):
				owner_player_char.heal(heal_amount)
		
		# --- Apply Status Effects on Hit ---
		if _received_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy_target.status_effect_component):
			var status_apps: Array = _received_stats.get(&"on_hit_status_applications", [])
			var global_status_effect_chance_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)

			for app_data_res in status_apps:
				var app_data = app_data_res as StatusEffectApplicationData
				if is_instance_valid(app_data):
					var final_application_chance = app_data.application_chance + global_status_effect_chance_add
					final_application_chance = clampf(final_application_chance, 0.0, 1.0) # Clamp between 0 and 1.
					
					if randf() < final_application_chance:
						enemy_target.status_effect_component.apply_effect(
							load(app_data.status_effect_resource_path) as StatusEffectData,
							owner_player_char, # Source of the effect (the player).
							_received_stats, # Pass weapon stats for scaling of the status effect.
							app_data.duration_override,
							app_data.potency_override
						)
						# print("SparkProjectile: Applied status from '", app_data.status_effect_resource_path, "' to enemy.") # Debug print.
		
		# Spark projectile dissipates on first hit (no pierce, no bounce for this one)
		call_deferred("queue_free") 
	elif body.is_in_group("world_obstacles"):
		# Spark projectile dissipates on hitting obstacles
		call_deferred("queue_free")
