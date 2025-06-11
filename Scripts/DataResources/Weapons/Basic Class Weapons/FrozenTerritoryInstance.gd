# FrozenTerritoryInstance.gd
# This script controls a single orbiting instance of Frozen Territory.
#
# UPDATED: Passes weapon tags to PlayerStats.get_calculated_player_damage for tag-specific damage modifiers.
# UPDATED: Integrates GLOBAL_LIFESTEAL_PERCENT for healing.
# UPDATED: Integrates GLOBAL_STATUS_EFFECT_CHANCE_ADD for status effect application.
# UPDATED: Uses PlayerStatKeys for all stat lookups.
# FIXED: Corrected how owner_player_stats is assigned and accessed to resolve "Identifier not declared" errors.
# FIXED: Declared 'lifetime' variable within the initialize function's scope.

class_name FrozenTerritoryInstance
extends Area2D # This remains Area2D as its movement is orbit-based, not physics-driven

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") # Ensure this is the correct node name for your CollisionShape

# --- Orbit Properties ---
var owner_player: PlayerCharacter # Holds reference to the PlayerCharacter node
var _owner_player_stats: PlayerStats # Holds direct reference to the PlayerStats node
var specific_weapon_stats: Dictionary # Stores the calculated weapon stats passed from controller
var orbit_radius: float = 75.0
var rotation_speed: float = 1.0 # Radians per second
var current_angle: float = 0.0

# --- Attack Properties ---
var damage_on_contact: int = 0 # Will be set by calculation

var _enemies_hit: Array[Node2D] = [] # To prevent multiple hits on the same enemy per frame/tick

func _ready():
	if not is_instance_valid(animated_sprite):
		push_warning("FrozenTerritoryInstance: AnimatedSprite2D missing.")
	if not is_instance_valid(collision_shape):
		push_error("FrozenTerritoryInstance: CollisionShape2D missing! Attack will not register hits.");
		call_deferred("queue_free"); return # Queue free if essential node is missing

	collision_shape.disabled = false # Enable collision by default
	body_entered.connect(Callable(self, "_on_body_entered"))


# This function is called by the controller that spawns this instance
# p_owner: Reference to the PlayerCharacter node.
# p_stats: The *calculated* weapon-specific stats dictionary from WeaponManager.
# start_angle: The initial angle for this instance in the orbit.
func initialize(p_owner: PlayerCharacter, p_stats: Dictionary, start_angle: float):
	owner_player = p_owner # Assign the PlayerCharacter reference
	_owner_player_stats = p_owner.player_stats # FIXED: Assign the direct PlayerStats reference from the PlayerCharacter
	specific_weapon_stats = p_stats # Store the calculated weapon stats
	
	if not is_instance_valid(owner_player) or not is_instance_valid(_owner_player_stats): # Check both refs
		push_error("FrozenTerritoryInstance: Player or PlayerStats invalid during initialization. Cannot calculate stats.");
		call_deferred("queue_free"); return

	# Use PlayerStatKeys for stat lookups and leverage calculated stats
	orbit_radius = float(specific_weapon_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ORBIT_RADIUS], 75.0))
	
	var rotation_duration = float(specific_weapon_stats.get(&"rotation_duration", 3.0)) # Assuming rotation_duration is a direct key
	if rotation_duration > 0:
		rotation_speed = TAU / rotation_duration
	
	current_angle = start_angle
	
	# --- Damage Calculation using unified method ---
	var weapon_damage_percent = float(specific_weapon_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 0.5))
	var weapon_tags: Array[StringName] = specific_weapon_stats.get(&"tags", []) # Retrieve weapon tags
	damage_on_contact = int(round(maxf(1.0, _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags)))) # Pass tags

	# --- LIFETIME LOGIC ---
	# Use base_lifetime from specific_weapon_stats (already calculated by WeaponManager)
	var base_lifetime_from_stats = float(specific_weapon_stats.get(&"base_lifetime", 3.0)) # Make sure base_lifetime is in blueprint
	
	# Apply player's global effect duration multiplier
	var duration_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER) # Use get_final_stat
	var lifetime: float = base_lifetime_from_stats * duration_multiplier # FIXED: Declare lifetime here.
	
	var instance_lifetime_timer = get_tree().create_timer(lifetime, true, false, true)
	if not is_instance_valid(instance_lifetime_timer):
		push_error("FrozenTerritoryInstance: Failed to create lifetime timer. Instance may persist indefinitely.");
	else:
		instance_lifetime_timer.timeout.connect(Callable(self, "queue_free")) # Connect to queue_free directly

	# Debug print to confirm initialization and stats
	print("FrozenTerritoryInstance: Initialized. Damage: ", damage_on_contact, ", Orbit Radius: ", orbit_radius, ", Lifetime: ", lifetime)


func _physics_process(delta: float):
	if not is_instance_valid(owner_player):
		queue_free()
		return
	
	current_angle += rotation_speed * delta
	
	var offset = Vector2.RIGHT.rotated(current_angle) * orbit_radius
	global_position = owner_player.global_position + offset

func _on_body_entered(body: Node2D):
	# Allow multiple hits if pierce_count is > 0, otherwise single hit per enemy.
	# For an aura-like weapon, you might want to hit multiple enemies over time,
	# but avoid hitting the *same* enemy on consecutive frames if it's not a tick-based area.
	if _enemies_hit.has(body): return # Prevent multiple hits on the same enemy per frame

	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if not is_instance_valid(enemy_target) or enemy_target.is_dead(): return
		
		_enemies_hit.append(enemy_target) # Add to list of hit enemies

		var owner_player_char = owner_player # Direct reference to PlayerCharacter
		
		# Prepare attack stats to pass to the enemy's take_damage method.
		# This includes armor penetration from the player's stats.
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}

		# Take damage
		enemy_target.take_damage(damage_on_contact, owner_player_char, attack_stats_for_enemy)
		
		# --- Apply Lifesteal ---
		var global_lifesteal_percent = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
		if global_lifesteal_percent > 0:
			var heal_amount = damage_on_contact * global_lifesteal_percent
			if is_instance_valid(owner_player_char) and owner_player_char.has_method("heal"):
				owner_player_char.heal(heal_amount)
		
		# --- Apply Status Effects on Hit ---
		# Iterate through the 'on_hit_status_applications' array from WeaponManager.
		if specific_weapon_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy_target.status_effect_component):
			var status_apps: Array = specific_weapon_stats.get(&"on_hit_status_applications", [])
			var global_status_effect_chance_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)

			for app_data_res in status_apps:
				var app_data = app_data_res as StatusEffectApplicationData
				if is_instance_valid(app_data):
					# Combine base application chance with global status effect chance addition.
					var final_application_chance = app_data.application_chance + global_status_effect_chance_add
					final_application_chance = clampf(final_application_chance, 0.0, 1.0) # Clamp between 0 and 1.
					
					if randf() < final_application_chance:
						enemy_target.status_effect_component.apply_effect(
							load(app_data.status_effect_resource_path) as StatusEffectData, # Load StatusEffectData from path
							owner_player_char, # Source of the effect (the player)
							specific_weapon_stats, # Pass weapon stats for scaling of the status effect
							app_data.duration_override,
							app_data.potency_override
						)
						# print("FrozenTerritoryInstance: Applied status from '", app_data.status_effect_resource_path, "' to enemy.") # Debug print.
