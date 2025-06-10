# SparkProjectile.gd
# Behavior for the Wizard's Spark projectile.
# A basic magical projectile that seeks a target.
# UPDATED: Uses PlayerStatKeys for stat lookups.
# UPDATED: Leverages PlayerStats.get_calculated_player_damage for unified damage calculation.
# UPDATED: Uses cached 'current_' properties from PlayerStats where appropriate.
# UPDATED: Passes attack_stats_for_enemy for armor penetration.

class_name SparkProjectile
extends Area2D

# These will be set in _apply_all_stats_effects
var final_damage_amount: int = 0
var final_speed: float = 0.0
var final_applied_scale: Vector2 = Vector2(1,1)
var direction: Vector2 = Vector2.RIGHT # Will be set by set_attack_properties

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer") as Timer
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D # Ensure this is the correct node name for your CollisionShape

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

	# If set_attack_properties was called before _ready (e.g., if instanced via add_child then set properties),
	# we can apply stats immediately. Otherwise, it will be called after _ready.
	if _stats_have_been_set:
		_apply_all_stats_effects()

func _physics_process(delta: float):
	global_position += direction * final_speed * delta

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
	final_damage_amount = int(round(_owner_player_stats.get_calculated_player_damage(weapon_damage_percent)))
	
	# --- Speed Calculation ---
	var base_w_speed = _received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SPEED], 250.0)
	var p_proj_spd_mult = _owner_player_stats.current_projectile_speed_multiplier # Use cached current_ stat
	final_speed = base_w_speed * p_proj_spd_mult
	
	# --- Scale Calculation ---
	var base_scale_x = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_X], 1.0))
	var base_scale_y = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_Y], 1.0))
	var p_proj_size_mult = _owner_player_stats.current_projectile_size_multiplier # Use cached current_ stat
	final_applied_scale.x = base_scale_x * p_proj_size_mult
	final_applied_scale.y = base_scale_y * p_proj_size_mult
	
	_apply_visual_scale()
	
	# --- Lifetime Calculation ---
	var base_lifetime = float(_received_stats.get(&"base_lifetime", 1.5)) # Assuming base_lifetime is a direct key
	var duration_mult = _owner_player_stats.current_effect_duration_multiplier # Use cached current_ stat
	lifetime_timer.wait_time = base_lifetime * duration_mult
	
	# Ensure timer is started if it was already created by _ready() but not yet started
	if is_instance_valid(lifetime_timer) and lifetime_timer.is_stopped():
		lifetime_timer.start()

func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_scale
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale

func _on_body_entered(body: Node2D):
	# The spark dissipates on the first thing it hits.
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		var enemy_target = body as BaseEnemy
		if not is_instance_valid(enemy_target) or enemy_target.is_dead(): return

		var owner_player = _owner_player_stats.get_parent() if is_instance_valid(_owner_player_stats) else null
		
		# Prepare attack stats to pass to the enemy's take_damage method.
		# This includes armor penetration from the player's stats.
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.current_armor_penetration # Use cached current_ stat
			# Add any other relevant attack properties here (e.g., status application chance)
		}

		enemy_target.take_damage(final_damage_amount, owner_player, attack_stats_for_enemy)
		queue_free()
	elif body.is_in_group("world_obstacles"):
		queue_free()
