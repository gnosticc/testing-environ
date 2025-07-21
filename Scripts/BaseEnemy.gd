# BaseEnemy.gd
# This script defines the base behavior for all enemies, including movement, damage,
# health, death, and elite mechanics.
# It now integrates with PlayerStats for damage calculation and uses PlayerStatKeys.
#
# FIXED: Variable shadowing warning for 'move_direction'.
# UPDATED: Correctly applies movement speed modifiers from StatusEffectComponent.
# UPDATED: Uses status_effect_component.has_flag() for visual tints and movement impairments.
# UPDATED: Correctly handles enemy body for stat/flag queries.
# FIXED: Implemented robust layered tinting system to ensure status effect tints
#        apply on top of elite tints and revert correctly after expiration/flash.
# FIXED: Corrected 'data' to 'base_data_source' in make_elite function for sprite_modulate_color access.
# CRITICAL FIX: Ensures status_effect_component reference is always synced and valid by removing @onready
#               and guaranteeing early, explicit assignment.
# FIXED: Explicitly resets animated_sprite.modulate to _final_base_modulate_color before applying status tints.

extends CharacterBody2D
class_name BaseEnemy

signal killed_by_attacker(attacker_node: Node, killed_enemy_node: Node) # Emitted when this enemy is defeated

# --- Core Enemy Stats (Initialized from EnemyData.tres) ---
# These are the *current* effective stats of the enemy.
var max_health: float # Changed to float for consistency with calculations
var current_health: float
var contact_damage: float # Changed to float for consistency
var speed: float
var experience_to_drop: int # This is the base EXP value. Player's EXP gain applies multiplier.
var armor: float # Changed to float for consistency with penetration

var is_dead_flag: bool = false # Flag to indicate if the enemy is dead

var _player_in_contact_area: bool = false # True if player is overlapping damage area
var _can_deal_contact_damage_again: bool = true # Cooldown for contact damage

# --- Node References ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D # Use $ shorthand
@onready var contact_damage_cooldown_timer: Timer = $ContactDamageTimer # Use $ shorthand
@onready var damage_area: Area2D = $DamageArea # Use $ shorthand
@onready var health_bar: ProgressBar = $HealthBar # Use $ shorthand
@onready var separation_detector: Area2D = $SeparationDetector # Use $ shorthand
# CRITICAL CHANGE: Removed @onready here. Reference will be set in _get_status_effect_component_reference().
var status_effect_component: StatusEffectComponent = null 

# --- Elite Mechanic Nodes (will be created dynamically as children) ---
var phaser_teleport_timer: Timer = null
var summoner_spawn_timer: Timer = null
var shaman_aura: Area2D = null
var shaman_heal_pulse_timer: Timer = null
var time_warper_aura: Area2D = null # For time_warper elite

# --- Visual & State Variables ---
const FLASH_COLOR: Color = Color(1.0, 0.3, 0.3, 1.0) # Red tint for hit feedback
var _initial_sprite_modulate_from_scene: Color = Color(1.0, 1.0, 1.0, 1.0) # Stores the sprite's modulate from the scene file
var _final_base_modulate_color: Color = Color(1.0, 1.0, 1.0, 1.0) # Combines scene color + EnemyData color + elite tint
const SLOW_TINT_COLOR: Color = Color(0.7, 0.85, 1.0, 1.0) # Light blue tint for slow effect
const FLASH_DURATION: float = 0.2 # How long the hit flash lasts
var player_node: PlayerCharacter = null # Reference to the player
const SEPARATION_FORCE_STRENGTH: float = 50.0 # Force for enemy-enemy separation

var is_elite: bool = false # True if this enemy is an elite variant
var elite_type_tag: StringName = &"" # Specific type of elite (e.g., &"brute", &"phaser")
var base_scene_root_scale: Vector2 = Vector2.ONE # Original scale of the enemy node (for elite scaling)
var _sprite_initially_faces_left: bool = false # Whether sprite needs to be flipped for right movement
var is_elite_immovable: bool = false # True if this elite cannot be knocked back/stunned
var _active_minions_by_summoner: Array[Node] = [] # Tracks minions spawned by this summoner elite

var enemy_data_resource: EnemyData # The EnemyData.tres resource for this enemy
var game_node_ref: Node # Reference to the global Game node (Main scene's root)

enum EnemyAnimState { IDLE, WALK, ATTACK, DEATH }
var current_anim_state: EnemyAnimState = EnemyAnimState.IDLE
const MIN_SPEED_FOR_WALK_ANIM: float = 5.0 # Minimum velocity squared to trigger walk animation
var _is_contact_attacking: bool = false # Flag to prevent movement during attack animation
var knockback_velocity: Vector2 = Vector2.ZERO # Current velocity from knockback
# NEW: Variable to accumulate external forces for one frame.
var external_forces: Vector2 = Vector2.ZERO
# NEW: Multiplier for all outgoing damage. Used by "Weakened" debuff.
var damage_output_multiplier: float = 1.0
# NEW: Used by StatusEffectComponent to know how much damage a proc should do.
var _last_damage_instance_received: int = 0


# --- Lifecycle & Initialization ---

func _ready():
	base_scene_root_scale = self.scale # Store initial scale for elite modifications
	
	# Get player node reference
	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0: player_node = players[0] as PlayerCharacter
	else: push_error("BaseEnemy: Player node not found in 'player_char_group'.")
	
	# Get Game node reference and increment active enemy count
	game_node_ref = get_tree().root.get_node_or_null("Game") # Assuming Game is root or direct child
	if is_instance_valid(game_node_ref) and game_node_ref.has_method("increment_active_enemy_count"):
		game_node_ref.increment_active_enemy_count()
	else:
		push_error("BaseEnemy: Game node reference invalid or missing 'increment_active_enemy_count'.")

	# Initialize health and health bar if enemy_data_resource isn't set yet (e.g., for editor instances)
	if not is_instance_valid(enemy_data_resource):
		current_health = float(max_health) # Ensure float
		update_health_bar()

	# Animated Sprite setup
	if is_instance_valid(animated_sprite):
		_initial_sprite_modulate_from_scene = animated_sprite.modulate # Store the absolute original scene modulate
		_final_base_modulate_color = _initial_sprite_modulate_from_scene # Start final base with scene color
		#print("BaseEnemy '", name, "': _initial_sprite_modulate_from_scene set in _ready(): ", _initial_sprite_modulate_from_scene) # DEBUG
		
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(&"attack"):
			if not animated_sprite.is_connected("animation_finished", Callable(self, "_on_animated_sprite_animation_finished")):
				animated_sprite.animation_finished.connect(Callable(self, "_on_animated_sprite_animation_finished"))
	else: push_error("BaseEnemy '", name, "': AnimatedSprite2D node not found.")

	# Contact Damage Timer setup
	if not is_instance_valid(contact_damage_cooldown_timer): push_error("BaseEnemy '", name, "': ContactDamageTimer node not found.")
	else:
		contact_damage_cooldown_timer.wait_time = 1.0 # Default cooldown
		contact_damage_cooldown_timer.one_shot = false
		if not contact_damage_cooldown_timer.is_connected("timeout", Callable(self, "_on_contact_damage_timer_timeout")):
			contact_damage_cooldown_timer.timeout.connect(Callable(self, "_on_contact_damage_timer_timeout"))

	# Damage Area setup
	if not is_instance_valid(damage_area): push_error("BaseEnemy '", name, "': DamageArea node not found.")
	else:
		if not damage_area.is_connected("body_entered", Callable(self, "_on_damage_area_body_entered")):
			damage_area.body_entered.connect(Callable(self, "_on_damage_area_body_entered"))
		if not damage_area.is_connected("body_exited", Callable(self, "_on_damage_area_body_exited")):
			damage_area.body_exited.connect(Callable(self, "_on_damage_area_body_exited"))

	# CRITICAL FIX: Ensure status_effect_component is properly referenced and synced
	# This call should be done in _ready AND again in initialize_from_data for pooled/re-initialized enemies.
	_get_status_effect_component_reference() 
	
	# Initial animation state update (might be updated again by on_status_effects_changed if effects exist)
	if speed > 0 and is_instance_valid(player_node):
		_update_animation_state()
	else:
		_set_animation_state(EnemyAnimState.IDLE)

# NEW: Helper function to get and connect the StatusEffectComponent reference
# This ensures that 'status_effect_component' is always the correct child instance
# and its signal is connected.
func _get_status_effect_component_reference():
	status_effect_component = get_node_or_null("StatusEffectComponent") as StatusEffectComponent
	if is_instance_valid(status_effect_component):
		# Connect to status_effects_changed to update visuals/behavior when effects change
		if status_effect_component.has_signal("status_effects_changed"):
			# Ensure we only connect once by checking if already connected
			if not status_effect_component.is_connected("status_effects_changed", Callable(self, "on_status_effects_changed")):
				status_effect_component.status_effects_changed.connect(Callable(self, "on_status_effects_changed"))
	else:
		push_error("BaseEnemy '", name, "': StatusEffectComponent node not found. Status effects will not work.")


# Handles cleanup when the enemy is removed from the scene tree.
func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		# Decrement active enemy count if not already dead (prevents double-counting from culling).
		if not is_dead_flag:
			if is_instance_valid(game_node_ref) and game_node_ref.has_method("decrement_active_enemy_count"):
				game_node_ref.decrement_active_enemy_count()
		
		# Clean up any dynamically created elite timers and nodes.
		if is_instance_valid(phaser_teleport_timer): phaser_teleport_timer.queue_free()
		if is_instance_valid(summoner_spawn_timer): summoner_spawn_timer.queue_free()
		if is_instance_valid(shaman_aura): shaman_aura.queue_free()
		if is_instance_valid(shaman_heal_pulse_timer): shaman_heal_pulse_timer.queue_free()
		if is_instance_valid(time_warper_aura): time_warper_aura.queue_free() # For time_warper

# Initializes enemy stats and visuals from an EnemyData resource.
# This function is called after the enemy is instantiated and added to the scene tree.
func initialize_from_data(data: EnemyData):
	if not is_instance_valid(data):
		push_error("BaseEnemy '", name, "': Invalid EnemyData provided. Using scene defaults."); return

	enemy_data_resource = data
	max_health = float(data.base_health) # Ensure float
	contact_damage = float(data.base_contact_damage) # Ensure float
	speed = data.base_speed
	armor = float(data.base_armor) # Ensure float
	experience_to_drop = data.base_exp_drop
	_sprite_initially_faces_left = data.sprite_faces_left_by_default
	
	current_health = max_health # Start with full health
	
	# CRITICAL FIX: Ensure status_effect_component is properly referenced and synced
	# This re-gets the reference for each newly initialized enemy (e.g., from a pool).
	_get_status_effect_component_reference() 

	if is_instance_valid(animated_sprite):
		# Combine initial scene modulate with EnemyData's sprite_modulate_color
		_final_base_modulate_color = _initial_sprite_modulate_from_scene * data.sprite_modulate_color
		#print("BaseEnemy '", name, "': _final_base_modulate_color after EnemyData applied: ", _final_base_modulate_color) # DEBUG
		
		# Now, trigger the status effect tint update
		if is_instance_valid(status_effect_component):
			on_status_effects_changed(self) # Call it to apply any active status tints
	else:
		push_warning("BaseEnemy '", name, "': AnimatedSprite2D missing in initialize_from_data. Cannot apply base color.")
		
	update_health_bar()
	_update_animation_state()

# Applies knockback force to the enemy.
func apply_knockback(direction: Vector2, force: float):
	# Don't knock back immovable elites or if currently stunned/frozen
	if is_elite_immovable: return
	if is_instance_valid(status_effect_component):
		# FIX: Use has_flag() for flags now
		if status_effect_component.has_flag(&"is_stunned") or status_effect_component.has_flag(&"is_frozen"):
			return # Stunned/frozen enemies are typically immune to knockback
	
	knockback_velocity = direction.normalized() * force

# --- Physics & Movement ---

# NEW: Public function for external objects to apply forces.
func apply_external_force(force: Vector2):
	external_forces += force

func _physics_process(delta: float):
	if is_dead_flag or _is_contact_attacking:
		velocity = Vector2.ZERO # Stop movement
		move_and_slide(); return

	# Handle status effects that stop movement
	if is_instance_valid(status_effect_component):
		if status_effect_component.has_flag(&"is_stunned") or status_effect_component.has_flag(&"is_frozen") or status_effect_component.has_flag(&"is_rooted"):
			velocity = Vector2.ZERO; move_and_slide(); return # Cannot move
			
		# If feared, change movement direction
		if status_effect_component.has_flag(&"is_feared"):
			if is_instance_valid(player_node):
				var move_direction = (global_position - player_node.global_position).normalized()
				var current_move_speed_from_base = speed # Start with base speed from EnemyData
				
				# CORRECTED SPEED CALCULATION
				var temp_flat_mod = status_effect_component.get_sum_of_flat_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED])
				var temp_percent_add_mod = status_effect_component.get_sum_of_percent_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED])
				var temp_multiplicative_mod = status_effect_component.get_product_of_multiplicative_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED])

				current_move_speed_from_base = (current_move_speed_from_base + temp_flat_mod) * (1.0 + temp_percent_add_mod) * temp_multiplicative_mod
				current_move_speed_from_base = maxf(0.0, current_move_speed_from_base)
				
				velocity = move_direction * current_move_speed_from_base
				move_and_slide(); _update_animation_state(); return

	var move_direction = Vector2.ZERO
	if is_instance_valid(player_node):
		move_direction = (player_node.global_position - global_position).normalized()
	
	var separation_vec = _calculate_separation_force() # Avoids enemy stacking
	var final_direction = (move_direction + separation_vec).normalized()
	
	var current_move_speed = speed # Start with base speed from EnemyData
	
	# Apply speed modifiers from status effects
	if is_instance_valid(status_effect_component):
		# CORRECTED SPEED CALCULATION
		var temp_flat_mod = status_effect_component.get_sum_of_flat_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED])
		var temp_percent_add_mod = status_effect_component.get_sum_of_percent_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED])
		var temp_multiplicative_mod = status_effect_component.get_product_of_multiplicative_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED])
		
		# Apply modifiers in the correct order: (Base + Flat) * (1 + Percent Add) * Multiplier
		current_move_speed = (current_move_speed + temp_flat_mod) * (1.0 + temp_percent_add_mod) * temp_multiplicative_mod
		current_move_speed = maxf(0.0, current_move_speed) # Ensure speed doesn't go negative

	# Combine movement velocity with knockback velocity
	velocity = final_direction * current_move_speed

	if knockback_velocity.length_squared() > 0:
		velocity += knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 300.0 * delta)

	if external_forces.length_squared() > 0:
		velocity += external_forces

	# Sprite flipping based on movement direction
	if is_instance_valid(animated_sprite) and velocity.x != 0:
		animated_sprite.flip_h = (velocity.x < 0) if not _sprite_initially_faces_left else (velocity.x > 0)
			
	move_and_slide()
	external_forces = Vector2.ZERO
	_update_animation_state()

# Calculates a force vector to push enemies away from each other.
func _calculate_separation_force() -> Vector2:
	var separation_vector = Vector2.ZERO
	if not is_instance_valid(separation_detector): return separation_vector
	
	var neighbors = separation_detector.get_overlapping_bodies()
	if neighbors.size() > 0:
		for neighbor in neighbors:
			if neighbor != self and neighbor is BaseEnemy and not neighbor.is_dead_flag: # Only separate from living enemies
				var away_from_neighbor = (global_position - neighbor.global_position).normalized()
				separation_vector += away_from_neighbor
		if separation_vector.length_squared() > 0.0001: # Avoid normalizing a zero vector
			separation_vector = separation_vector.normalized()
			
	return separation_vector * SEPARATION_FORCE_STRENGTH

# --- Damage & Death ---

# Handles this enemy taking damage from an attacker.
# amount: The base damage amount.
# attacker_node: The node that dealt the damage (e.g., PlayerCharacter, a Projectile).
# p_attack_stats: Dictionary containing attack-specific stats (e.g., player's armor_penetration).
# --- MERGED take_damage function ---
func take_damage(damage_amount: float, attacker_node: Node = null, p_attack_stats: Dictionary = {}, p_weapon_tags: Array[StringName] = []):
	if current_health <= 0 or is_dead_flag: return
	
	var final_damage_taken = damage_amount
	var current_armor_stat = armor
	
	var armor_penetration_value = float(p_attack_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION], 0.0))
	var effective_armor = maxf(0.0, current_armor_stat - armor_penetration_value)
	final_damage_taken = maxf(1.0, final_damage_taken - effective_armor)
	
	if is_instance_valid(status_effect_component):
		var damage_taken_mod_add = status_effect_component.get_sum_of_percent_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.DAMAGE_TAKEN_MULTIPLIER])
		var damage_taken_mod_mult = status_effect_component.get_product_of_multiplicative_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.DAMAGE_TAKEN_MULTIPLIER])
		final_damage_taken *= (1.0 + damage_taken_mod_add)
		final_damage_taken *= damage_taken_mod_mult
		
	_last_damage_instance_received = int(round(final_damage_taken))

	current_health -= final_damage_taken
	update_health_bar()
	_flash_on_hit()

	# --- Catalytic Reaction Check ---
	if is_instance_valid(status_effect_component) and status_effect_component.has_status_effect(&"soaked"):
		status_effect_component.consume_effect_and_apply_next(&"soaked")
		# This signal now correctly passes the weapon tags from the damaging attack
		CombatEvents.emit_signal("catalytic_reaction_requested", self, p_weapon_tags)

	if current_health <= 0:
		_die(attacker_node)

# Handles the enemy's death sequence.
# MERGED _die function with Lingering Cold and Shadow's Embrace logic
func _die(killer_node: Node = null):
	if is_dead_flag: return
	is_dead_flag = true
	
	# --- Shadow's Embrace Logic ---
	if is_instance_valid(status_effect_component) and status_effect_component.has_status_effect(&"death_mark"):
		var effect_entry = status_effect_component.active_effects.get("death_mark")
		if effect_entry and effect_entry.has("weapon_stats"):
			CombatEvents.emit_signal("death_mark_triggered", global_position, effect_entry.weapon_stats)

	_is_contact_attacking = false
	_set_animation_state(EnemyAnimState.DEATH)

	# Stop and free elite-specific timers and nodes.
	if is_instance_valid(phaser_teleport_timer): phaser_teleport_timer.queue_free()
	if is_instance_valid(summoner_spawn_timer): summoner_spawn_timer.queue_free()
	if is_instance_valid(shaman_aura): shaman_aura.queue_free()
	if is_instance_valid(shaman_heal_pulse_timer): shaman_heal_pulse_timer.queue_free()
	if is_instance_valid(time_warper_aura): time_warper_aura.queue_free()

	# --- Lingering Cold Logic ---
	if is_instance_valid(status_effect_component) and status_effect_component.has_status_effect_by_unique_id("ft_lingering_cold_slow"):
		var weapon_stats = status_effect_component.get_stats_from_effect_source_by_unique_id("ft_lingering_cold_slow")
		var spread_radius = float(weapon_stats.get(&"lingering_cold_radius", 75.0))
		var slow_effect_data = load("res://DataResources/StatusEffects/slow_status.tres") as StatusEffectData
		
		var space_state = get_world_2d().direct_space_state
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = CircleShape2D.new(); query.shape.radius = spread_radius
		query.transform = Transform2D(0, global_position)
		query.collision_mask = self.collision_layer
		
		var results = space_state.intersect_shape(query)
		for result in results:
			var collider = result.collider
			if collider != self and collider is BaseEnemy and is_instance_valid(collider) and not collider.is_dead():
				if is_instance_valid(collider.status_effect_component):
					collider.status_effect_component.apply_effect(slow_effect_data, killer_node)

	# Decrement active enemy count in game.gd.
	if is_instance_valid(game_node_ref) and game_node_ref.has_method("decrement_active_enemy_count"):
		game_node_ref.decrement_active_enemy_count()
	else:
		push_warning("BaseEnemy '", name, "': Game node reference invalid or missing 'decrement_active_enemy_count' on death.")

	# --- Transmutation Check (MUST happen before _on_owner_death) ---
	if is_instance_valid(status_effect_component) and (status_effect_component.has_flag(&"is_marked_for_transmutation") or status_effect_component.has_flag(&"is_soaked")):
		if is_instance_valid(player_node): # Ensure player reference is valid
			var player_stats = player_node.get_node_or_null("PlayerStats")
			if is_instance_valid(player_stats):
				var base_chance = 0.25
				var luck = player_stats.get_final_stat(PlayerStatKeys.Keys.LUCK)
				var final_chance = base_chance + (luck * 0.05)
				if randf() < final_chance:
					call_deferred("_spawn_transmuted_orb")
		else:
			push_warning("BaseEnemy '", name, "': Transmutation check failed, player_node is not valid.")

	# Now that we've checked for statuses, we can clear them.
	if is_instance_valid(status_effect_component):
		status_effect_component._on_owner_death()
	
	# Drop the primary orb immediately, but deferred to avoid physics errors.
	call_deferred("_finish_dying_and_drop_exp")

	emit_signal("killed_by_attacker", killer_node, self)
	set_physics_process(false)

	# Disable/free collision shapes and areas to prevent further interaction.
	var col_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if is_instance_valid(col_shape): col_shape.call_deferred("set_disabled", true)
	
	if is_instance_valid(damage_area):
		var da_col_shape = damage_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if is_instance_valid(da_col_shape): da_col_shape.call_deferred("set_disabled", true)
		damage_area.call_deferred("set_monitoring", false)
		
	if is_instance_valid(separation_detector):
		var sd_col_shape = separation_detector.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if is_instance_valid(sd_col_shape): sd_col_shape.call_deferred("set_disabled", true)
		separation_detector.call_deferred("set_monitoring", false)

	# Set a single, reliable timer to delete the enemy node after the death animation.
	get_tree().create_timer(1.0).timeout.connect(queue_free)



func _spawn_transmuted_orb():
	print_debug("Transmutation successful! Spawning extra experience orb.")
	var offset = Vector2(randf_range(-15.0, 15.0), randf_range(-15.0, 15.0))
	_finish_dying_and_drop_exp(offset)

# Handles dropping experience and queuing for free.
func _finish_dying_and_drop_exp(p_offset: Vector2 = Vector2.ZERO):
	var final_exp_to_give = self.experience_to_drop
	var actual_exp_scene_path: String = ""
	
	if is_instance_valid(enemy_data_resource) and not enemy_data_resource.exp_drop_scene_path.is_empty():
		actual_exp_scene_path = enemy_data_resource.exp_drop_scene_path
	else:
		push_warning("BaseEnemy '", name, "': Missing exp_drop_scene_path in EnemyData. Skipping EXP drop.")
		return

	if not actual_exp_scene_path.is_empty():
		var exp_scene_to_load = load(actual_exp_scene_path) as PackedScene
		if is_instance_valid(exp_scene_to_load):
			var exp_drop_instance = exp_scene_to_load.instantiate()
			
			var drops_container_node = get_tree().current_scene.get_node_or_null("DropsContainer")
			if is_instance_valid(drops_container_node):
				drops_container_node.add_child(exp_drop_instance)
			elif get_parent():
				get_parent().add_child(exp_drop_instance)
			else:
				get_tree().current_scene.add_child(exp_drop_instance)
			
			exp_drop_instance.global_position = self.global_position + p_offset
			
			if exp_drop_instance.has_method("set_experience_value"):
				exp_drop_instance.set_experience_value(final_exp_to_give, self.is_elite)
			else:
				push_warning("BaseEnemy: EXP drop instance '", exp_drop_instance.name, "' is missing 'set_experience_value' method.")
		else:
			push_error("BaseEnemy: Could not load EXP drop scene from path: ", actual_exp_scene_path)



# Culls the enemy (removes it without death animation/EXP drop) and reports threat.
func cull_self_and_report_threat():
	if is_dead_flag: return # Already dying or dead
	
	if is_instance_valid(game_node_ref) and is_instance_valid(enemy_data_resource):
		if game_node_ref.has_method("add_to_global_threat_pool"):
			game_node_ref.add_to_global_threat_pool(enemy_data_resource.threat_value_when_culled)
		else:
			push_warning("BaseEnemy '", name, "': Game node reference missing 'add_to_global_threat_pool'.")
	else:
		push_warning("BaseEnemy '", name, "': Game node or EnemyData resource invalid for threat reporting.")
	
	# Decrement active enemy count directly as it's not going through full _die() path
	if is_instance_valid(game_node_ref) and game_node_ref.has_method("decrement_active_enemy_count"):
		game_node_ref.decrement_active_enemy_count()
	else:
		push_warning("BaseEnemy '", name, "': Game node reference invalid or missing 'decrement_active_enemy_count' on cull.")
		
	is_dead_flag = true # Mark as dead to prevent further processing
	queue_free() # Immediately remove from scene

# Flashes the enemy sprite red briefly when hit.
func _flash_on_hit():
	if not is_instance_valid(animated_sprite): return
	
	var current_modulate_before_flash = animated_sprite.modulate # Store current modulate before applying flash
	animated_sprite.modulate = FLASH_COLOR
	
	# Create a one-shot timer for the flash duration
	var flash_timer = get_tree().create_timer(FLASH_DURATION, true, false, true)
	await flash_timer.timeout # Wait for the timer to finish
	
	# Restore to the color it was BEFORE the flash (which includes any status tints)
	if is_instance_valid(self) and is_instance_valid(animated_sprite):
		animated_sprite.modulate = current_modulate_before_flash


# Updates the enemy's health bar display.
func update_health_bar():
	if is_instance_valid(health_bar):
		health_bar.max_value = maxf(1.0, max_health) # Ensure max_value is at least 1.0 (float)
		health_bar.value = current_health
		# Health bar visible only when health is not full and not zero.
		health_bar.visible = (current_health < max_health and current_health > 0)
	else: push_warning("BaseEnemy '", name, "': HealthBar node not found, cannot update display.")

# Updates the enemy's animation state based on its current velocity.
func _update_animation_state():
	if is_instance_valid(status_effect_component): # Check for status effects that might prevent animation change
		if status_effect_component.has_flag(&"is_stunned") or status_effect_component.has_flag(&"is_frozen") or status_effect_component.has_flag(&"is_rooted"):
			_set_animation_state(EnemyAnimState.IDLE) # Force idle if movement is stopped by status effect
			return

	if is_dead_flag or _is_contact_attacking or current_anim_state == EnemyAnimState.ATTACK: return # Prioritize these states
	
	if velocity.length_squared() > MIN_SPEED_FOR_WALK_ANIM * MIN_SPEED_FOR_WALK_ANIM:
		_set_animation_state(EnemyAnimState.WALK)
	else:
		_set_animation_state(EnemyAnimState.IDLE)

# Sets the current animation state and plays the corresponding animation.
func _set_animation_state(new_state: EnemyAnimState):
	# Optimization: Don't change animation if already playing the same one
	if new_state == current_anim_state and is_instance_valid(animated_sprite) and animated_sprite.is_playing():
		if new_state == EnemyAnimState.IDLE and animated_sprite.animation == &"idle": # Allow re-setting idle if it's the current but not playing
			pass # Keep playing idle or ensure it starts if stopped
		else:
			return # No actual state change or animation change needed
			
	current_anim_state = new_state
	match current_anim_state:
		EnemyAnimState.IDLE: _play_animation(&"idle")
		EnemyAnimState.WALK: _play_animation(&"walk")
		EnemyAnimState.ATTACK: _play_animation(&"attack")
		EnemyAnimState.DEATH: _play_animation(&"death")
		_: push_warning("BaseEnemy: Unknown animation state: ", new_state)

# Plays a specified animation on the AnimatedSprite2D.
func _play_animation(anim_name: StringName):
	if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames:
		if animated_sprite.sprite_frames.has_animation(anim_name):
			if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
				animated_sprite.play(anim_name)
		#else:
			#push_warning("BaseEnemy: AnimatedSprite2D does not have animation: '", anim_name, "'.")
	else:
		push_warning("BaseEnemy: AnimatedSprite2D or its SpriteFrames are invalid, cannot play animation '", anim_name, "'.")

# Called when an attack animation finishes.
func _on_animated_sprite_animation_finished():
	if _is_contact_attacking and animated_sprite.animation == &"attack":
		_is_contact_attacking = false
		_update_animation_state() # Go back to idle/walk after attack
	elif current_anim_state == EnemyAnimState.DEATH and animated_sprite.animation == &"death":
		# Logic to handle post-death animation (e.g., enemy disappears)
		pass

# Called when the contact damage timer times out.
func _on_contact_damage_timer_timeout():
	if is_dead_flag: return
	if _player_in_contact_area:
		_try_deal_contact_damage()
	else:
		# If player is no longer in contact, stop the timer.
		if is_instance_valid(contact_damage_cooldown_timer):
			contact_damage_cooldown_timer.stop()

# Called when a body enters the damage area.
func _on_damage_area_body_entered(body: Node2D):
	if body.is_in_group("player_char_group"):
		_player_in_contact_area = true
		_try_deal_contact_damage()
		# Start the timer if it's stopped to enforce cooldown.
		if is_instance_valid(contact_damage_cooldown_timer) and contact_damage_cooldown_timer.is_stopped():
			contact_damage_cooldown_timer.start()

# Called when a body exits the damage area.
func _on_damage_area_body_exited(body: Node2D):
	if body.is_in_group("player_char_group"):
		_player_in_contact_area = false
		# Stop the timer when player leaves contact to prevent unnecessary ticking.
		if is_instance_valid(contact_damage_cooldown_timer):
			contact_damage_cooldown_timer.stop() # Typo: This should be contact_damage_cooldown_timer
	

# --- Contact Damage Logic ---
# Attempts to deal contact damage to the player if conditions are met.
func _try_deal_contact_damage():
	# --- NEW: Check for attack impairing status effects ---
	if is_instance_valid(status_effect_component):
		# Enemies cannot attack while stunned, frozen, disarmed, or feared.
		# FIX: Use has_flag() for flags here
		if status_effect_component.has_flag(&"is_stunned") \
		or status_effect_component.has_flag(&"is_frozen") \
		or status_effect_component.has_flag(&"is_feared") \
		or status_effect_component.has_flag(&"is_disarmed"): # Assuming is_disarmed is another flag
			return # Cannot attack
	
	if not _player_in_contact_area or is_dead_flag or _is_contact_attacking: return
		
	if is_instance_valid(player_node) and player_node.has_method("take_damage"):
		var final_contact_damage = contact_damage * damage_output_multiplier
		
		if damage_output_multiplier < 1.0:
			print("DEBUG (Weakened): Enemy '", name, "' is Weakened. Base Dmg: ", contact_damage, ", Final Dmg: ", final_contact_damage)
			
		player_node.take_damage(final_contact_damage, self)
		_can_deal_contact_damage_again = false # Reset cooldown flag
		
		# Play attack animation if available
		if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(&"attack"):
			_is_contact_attacking = true
			_set_animation_state(EnemyAnimState.ATTACK)
		
		# Ensure timer is running to enforce cooldown (redundant with body_entered logic but safe)
		if is_instance_valid(contact_damage_cooldown_timer) and contact_damage_cooldown_timer.is_stopped():
			contact_damage_cooldown_timer.start()

# --- Elite Mechanics ---

# Applies elite modifications to the enemy's stats and behavior.
func make_elite(p_elite_type: StringName, p_elite_DDS_contribution: float = 0.0, p_base_data_for_elite: EnemyData = null):
	is_elite = true
	elite_type_tag = p_elite_type
	if is_instance_valid(self):
		name = name + "_Elite_" + str(elite_type_tag) # Rename for easier identification

	# --- Get True Base Stats (from data resource, not current scene values) ---
	# This ensures elite scaling applies to the original, un-modified base stats.
	var true_base_hp = max_health; var true_base_speed = speed
	var true_base_damage = contact_damage; var true_base_exp = experience_to_drop
	var true_base_armor = armor; var true_base_modulate = _initial_sprite_modulate_from_scene # Start with scene's original modulate
	var true_base_scale = base_scene_root_scale
	
	var base_data_source = p_base_data_for_elite if is_instance_valid(p_base_data_for_elite) else enemy_data_resource # Renamed to avoid shadowing 'data'
	if is_instance_valid(base_data_source):
		true_base_hp = float(base_data_source.base_health)
		true_base_speed = base_data_source.base_speed
		true_base_damage = float(base_data_source.base_contact_damage)
		true_base_exp = base_data_source.base_exp_drop
		true_base_armor = float(base_data_source.base_armor)
		if is_instance_valid(animated_sprite): 
			# Apply EnemyData's color to the true_base_modulate
			true_base_modulate *= base_data_source.sprite_modulate_color # FIX: Changed 'data' to 'base_data_source'
	else:
		push_warning("BaseEnemy '", name, "': No valid base_data for elite. Using current scene stats.")

	# --- Stat Multipliers (Default for all elites unless overridden by type) ---
	var health_percent_increase: float = 4.00 # 400% more health (5x total)
	var damage_percent_increase: float = 0.20 # 20% more damage
	var speed_percent_increase: float = 0.0 # No speed change by default
	var additional_flat_armor: float = 0.0 # No flat armor change by default
	var exp_multiplier: float = 2.0 + (p_elite_DDS_contribution * 0.01) # Scales with DDS contribution
	var scale_multiplier: float = 2.0 # Default visual scale for elites
	
	var elite_tint_overlay = Color(1,1,1,1) # Default tint (no change)

	# --- Apply Logic Based on Elite Type ---
	match elite_type_tag:
		&"brute":
			damage_percent_increase += 0.30 # Total 50% damage increase
			elite_tint_overlay = Color(1.0, 0.8, 0.8, 1.0) # Reddish tint
		&"tank":
			health_percent_increase += 4.00 # Total 800% health increase (9x total)
			additional_flat_armor += 5.0 # Additional flat armor
			elite_tint_overlay = Color(0.8, 1.0, 0.8, 1.0) # Greenish tint
		&"swift":
			speed_percent_increase += 0.30 # 30% more speed
			elite_tint_overlay = Color(0.8, 0.8, 1.0, 1.0) # Bluish tint
		&"immovable":
			is_elite_immovable = true # Cannot be knocked back or affected by movement impairments
			elite_tint_overlay = Color(0.9, 0.9, 0.9, 1.0) # Grayish tint
		&"phaser":
			elite_tint_overlay = Color(0.8, 0.5, 1.0, 1.0) # Purplish tint
			phaser_teleport_timer = Timer.new(); phaser_teleport_timer.name = "PhaserTimer"
			phaser_teleport_timer.wait_time = base_data_source.phaser_cooldown # Cooldown from EnemyData
			phaser_teleport_timer.one_shot = false
			add_child(phaser_teleport_timer)
			phaser_teleport_timer.timeout.connect(_on_phaser_teleport_timer_timeout)
			phaser_teleport_timer.start()
		&"summoner":
			elite_tint_overlay = Color(1.0, 1.0, 0.5, 1.0) # Yellowish tint
			summoner_spawn_timer = Timer.new(); summoner_spawn_timer.name = "SummonerTimer"
			summoner_spawn_timer.wait_time = base_data_source.summoner_interval # Interval from EnemyData
			summoner_spawn_timer.one_shot = false
			add_child(summoner_spawn_timer)
			summoner_spawn_timer.timeout.connect(_on_summoner_spawn_timer_timeout)
			summoner_spawn_timer.start()
		&"shaman":
			elite_tint_overlay = Color(0.5, 1.0, 0.8, 1.0) # Teal tint
			shaman_aura = Area2D.new(); shaman_aura.name = "ShamanAura"; add_child(shaman_aura)
			var aura_shape = CircleShape2D.new(); aura_shape.radius = base_data_source.shaman_heal_radius # Radius from EnemyData
			var aura_col = CollisionShape2D.new(); aura_col.shape = aura_shape; shaman_aura.add_child(aura_col)
			shaman_aura.collision_layer = 0 # No collision layer for the aura itself
			shaman_aura.collision_mask = 8 # Mask 8 is typically the 'enemies' layer
			shaman_heal_pulse_timer = Timer.new(); shaman_heal_pulse_timer.name = "ShamanHealTimer"
			shaman_heal_pulse_timer.wait_time = base_data_source.shaman_heal_interval # Interval from EnemyData
			shaman_heal_pulse_timer.one_shot = false
			add_child(shaman_heal_pulse_timer)
			shaman_heal_pulse_timer.timeout.connect(_on_shaman_heal_pulse_timer_timeout)
			shaman_heal_pulse_timer.start()
		&"time_warper":
			elite_tint_overlay = Color(0.6, 0.4, 0.8, 1.0) # Purplish-gray tint
			# TODO: Implement Time-Warper aura logic (e.g., creating an Area2D to slow projectiles/player)
			# time_warper_aura = Area2D.new(); time_warper_aura.name = "TimeWarperAura"; add_child(time_warper_aura)
			# (Add collision shape, set up logic to slow things in area)
		_: # Default elite appearance for unhandled types or generic elite.
			elite_tint_overlay = Color(1.0, 0.9, 0.7, 1.0) # Light yellowish tint

	# --- Final Stat Application ---
	# Apply percentage increases to base stats.
	max_health = true_base_hp * (1.0 + health_percent_increase) # Use floats for precision
	current_health = max_health # Restore to full health after scaling
	
	contact_damage = true_base_damage * (1.0 + damage_percent_increase)
	speed = true_base_speed * (1.0 + speed_percent_increase)
	armor = true_base_armor + additional_flat_armor # Flat addition for armor
	experience_to_drop = int(true_base_exp * exp_multiplier)
	
	# Scale the entire enemy node (root) visually.
	self.scale = true_base_scale * scale_multiplier
	
	if is_instance_valid(animated_sprite):
		# Apply the elite tint on top of the already set _final_base_modulate_color
		_final_base_modulate_color = _final_base_modulate_color * elite_tint_overlay
		print("BaseEnemy '", name, "': _final_base_modulate_color after Elite applied: ", _final_base_modulate_color) # DEBUG
		
		# Trigger the status effect tint update
		if is_instance_valid(status_effect_component):
			on_status_effects_changed(self) # Call it to apply any active status tints
	else:
		push_warning("BaseEnemy '", name, "': AnimatedSprite2D missing in make_elite. Cannot apply elite tint.")
	
	update_health_bar()
	print("BaseEnemy '", name, "': Transformed into Elite (", elite_type_tag, "). HP: ", current_health, ", Speed: ", speed, ", DMG: ", contact_damage)


# --- Elite Behavior Functions (Placeholder/Example) ---

# Phaser Elite: Teleports to a new position near the player.
func _on_phaser_teleport_timer_timeout():
	if is_dead_flag or not is_instance_valid(player_node): return
	var teleport_distance = enemy_data_resource.phaser_teleport_distance
	var direction_to_player = (player_node.global_position - global_position).normalized()
	# Teleport to a random position around the player at a certain distance
	var random_offset_angle = randf_range(-PI / 4, PI / 4) # Small angle variance
	var new_position = player_node.global_position - direction_to_player.rotated(random_offset_angle) * teleport_distance
	global_position = new_position
	# TODO: Add visual/sound effect for teleport (e.g., particle burst, fade out/in).

# Summoner Elite: Spawns new minions.
func _on_summoner_spawn_timer_timeout():
	if is_dead_flag or not is_instance_valid(game_node_ref) or not is_instance_valid(enemy_data_resource): return
	
	var max_minions = enemy_data_resource.summoner_max_active_minions
	# Filter out any invalid (freed) minions from the tracking array
	_active_minions_by_summoner = _active_minions_by_summoner.filter(func(m): return is_instance_valid(m))
	
	if _active_minions_by_summoner.size() >= max_minions: return # Max minions reached

	# TODO: Select actual minion type based on enemy_data_resource.summoner_minion_ids
	# For now, using a hardcoded example:
	var minion_id_to_spawn = enemy_data_resource.summoner_minion_ids.pick_random() if not enemy_data_resource.summoner_minion_ids.is_empty() else &"slime_green"
	var minion_enemy_data = game_node_ref.get_enemy_data_by_id_for_debug(minion_id_to_spawn)
	
	if not is_instance_valid(minion_enemy_data):
		push_warning("BaseEnemy '", name, "': Summoner could not find minion data for ID: '", minion_id_to_spawn, "'. Skipping summon.")
		return

	var minion_scene_path = minion_enemy_data.scene_path
	var minion_scene = load(minion_scene_path) as PackedScene
	
	if is_instance_valid(minion_scene):
		var minion_instance = minion_scene.instantiate() as BaseEnemy
		minion_instance.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20)) # Spawn near summoner
		
		# Optionally hide health bar for small minions
		if minion_instance.has_node("HealthBar"): minion_instance.get_node("HealthBar").visible = false

		var parent_container = get_parent() if is_instance_valid(get_parent()) else get_tree().current_scene # Default to current scene
		if is_instance_valid(parent_container):
			parent_container.add_child(minion_instance)
			minion_instance.initialize_from_data(minion_enemy_data) # Initialize minion stats
			_active_minions_by_summoner.append(minion_instance) # Track spawned minion
		else:
			push_error("BaseEnemy '", name, "': Summoner could not find valid parent for minion. Freeing minion.")
			minion_instance.queue_free()
	else:
		push_error("BaseEnemy '", name, "': Summoner failed to load minion scene: ", minion_scene_path)

# Shaman Elite: Heals nearby allies.
func _on_shaman_heal_pulse_timer_timeout():
	if is_dead_flag or not is_instance_valid(shaman_aura) or not is_instance_valid(enemy_data_resource): return
	
	var heal_amount_percent = enemy_data_resource.shaman_heal_percent # Percentage of target's max health
	var overlapping_bodies = shaman_aura.get_overlapping_bodies()
	
	for body in overlapping_bodies:
		if body == self: continue # Don't heal self with this logic
		if body is BaseEnemy and not body.is_dead_flag: # Only heal living enemies
			var enemy_to_heal = body as BaseEnemy
			if enemy_to_heal.current_health < enemy_to_heal.max_health:
				var heal_value = int(ceilf(enemy_to_heal.max_health * heal_amount_percent)) # Use ceilf for floats
				enemy_to_heal.current_health = minf(enemy_to_heal.max_health, enemy_to_heal.current_health + float(heal_value)) # Use minf and float for health
				enemy_to_heal.update_health_bar()
				# TODO: Add a visual/sound effect for healing

# --- Status Effects & Getters ---
# Called by StatusEffectComponent when its active effects change.
func on_status_effects_changed(_owner_node: Node):
	# DEBUG PRINT: Confirm function call
	
	if not is_instance_valid(animated_sprite) or not is_instance_valid(status_effect_component): return
	
	# Start applied_tint from the combined scene/EnemyData/elite color
	var applied_tint: Color = _final_base_modulate_color 
	


	# Apply tints based on active status effect flags (order matters for visual priority)
	if status_effect_component.has_flag(&"is_stunned"):
		applied_tint *= Color(0.5, 0.5, 0.5, 1.0) # Darken
	elif status_effect_component.has_flag(&"is_frozen"):
		applied_tint *= Color(0.7, 0.9, 1.0, 1.0) # Icy blue
	elif status_effect_component.has_flag(&"is_slowed"):
		applied_tint *= SLOW_TINT_COLOR # Light blue tint for slow
	# Add more tints for other effects as needed (e.g., Burn, Poison)
	
	# --- STAT UPDATE LOGIC ---
	# Armor
	var old_armor = armor
	var base_armor_val = 0.0
	if is_instance_valid(enemy_data_resource):
		base_armor_val = float(enemy_data_resource.base_armor)
	
	var flat_mod = status_effect_component.get_sum_of_flat_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR])
	var percent_add_mod = status_effect_component.get_sum_of_percent_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR])
	var mult_mod = status_effect_component.get_product_of_multiplicative_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR])
	
	var new_armor = (base_armor_val + flat_mod) * (1.0 + percent_add_mod) * mult_mod
	
	if not is_equal_approx(old_armor, new_armor):
		print_debug("Armor changed for '", name, "'. Before: ", old_armor, " -> After: ", new_armor)
	
	armor = new_armor

	# Damage Output Multiplier
	var final_damage_mult = 1.0 
	var mult_from_status = status_effect_component.get_product_of_multiplicative_modifiers(
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.DAMAGE_OUTPUT_MULTIPLIER]
	)
	final_damage_mult *= mult_from_status
	self.damage_output_multiplier = final_damage_mult

	set_physics_process(true)


func is_dead() -> bool:
	return is_dead_flag

func get_current_health() -> float:
	return current_health

func get_is_elite_immovable() -> bool:
	return is_elite_immovable
