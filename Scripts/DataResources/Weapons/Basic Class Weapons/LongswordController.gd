# LongswordController.gd
# This new controller script handles the unique logic for the Longsword,
# including Parry & Riposte, Blade Flurry, and Holy Infusion.
class_name LongswordController
extends Node2D

@export var longsword_attack_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
# NEW: Variable to hold a reference to the manager for connecting signals.
var _weapon_manager: WeaponManager

# This is the entry point called by WeaponManager
# FIX: Added p_weapon_manager as the fourth argument to match the call.
func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	if not is_instance_valid(longsword_attack_scene):
		push_error("LongswordController: longsword_attack_scene is not assigned!"); queue_free(); return

	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager # Store the reference

	# --- Parry & Riposte Logic ---
	var riposte_multiplier = 1.0
	if _specific_stats.get(&"has_parry_riposte", false):
		if _specific_stats.get("parry_riposte_bonus_active", false):
			riposte_multiplier = 3.0
		# The controller will set the flag for the next primary swing
		_specific_stats["parry_riposte_bonus_active"] = true

	# --- Spawn Primary Swing ---
	var primary_attack = _spawn_attack_instance(riposte_multiplier, true)
	if is_instance_valid(primary_attack):
		primary_attack.attack_hit_enemy.connect(_on_attack_hit_enemy)

	# --- Blade Flurry Logic ---
	if _specific_stats.get(&"has_blade_flurry", false):
		if randf() < float(_specific_stats.get(&"blade_flurry_chance", 0.0)):
			# Fire a second, identical swing after a short delay
			get_tree().create_timer(0.2, true, false, true).timeout.connect(
				_spawn_attack_instance.bind(1.0, false, primary_attack.global_transform)
			)

	# --- Holy Infusion Logic ---
	if _specific_stats.get(&"has_holy_infusion", false):
		var owner_player = _owner_player_stats.get_parent() as PlayerCharacter
		if is_instance_valid(owner_player) and is_instance_valid(owner_player.melee_aiming_dot):
			var opposite_local_pos = owner_player.melee_aiming_dot.position * -1
			var opposite_global_pos = owner_player.to_global(opposite_local_pos)
			var opposite_rotation = (owner_player.melee_aiming_dot.global_position - owner_player.global_position).angle() + PI
			var opposite_transform = Transform2D(opposite_rotation, opposite_global_pos)
			
			# Spawn the backward swing
			var opposite_swing = _spawn_attack_instance(riposte_multiplier, false, opposite_transform)
			
			# Check for Blade Flurry on the backward swing as well
			if is_instance_valid(opposite_swing) and _specific_stats.get(&"has_blade_flurry", false):
				if randf() < float(_specific_stats.get(&"blade_flurry_chance", 0.0)):
					get_tree().create_timer(0.2, true, false, true).timeout.connect(
						_spawn_attack_instance.bind(1.0, false, opposite_swing.global_transform)
					)

	# The controller's job is done after a brief moment to allow timers to start
	get_tree().create_timer(0.3).timeout.connect(queue_free)


func _spawn_attack_instance(p_riposte_mult: float, is_initial_swing: bool, p_transform_override = null) -> Node2D:
	var owner_player = _owner_player_stats.get_parent() as PlayerCharacter
	if not is_instance_valid(owner_player): return null

	var attack_instance = longsword_attack_scene.instantiate() as LongswordAttack
	owner_player.add_child(attack_instance)
	
	var final_transform: Transform2D
	var final_direction: Vector2
	
	# Determine transform and direction
	if p_transform_override != null and p_transform_override is Transform2D:
		final_transform = p_transform_override
	else:
		final_direction = (owner_player.get_global_mouse_position() - owner_player.global_position).normalized()
		if not is_instance_valid(owner_player.melee_aiming_dot):
			push_error("LongswordController: MeleeAimingDot node is invalid!")
			return null
		final_transform = Transform2D(final_direction.angle(), owner_player.melee_aiming_dot.global_position)
	
	attack_instance.global_transform = final_transform
	final_direction = Vector2.RIGHT.rotated(attack_instance.global_rotation)
	
	var stats_to_pass = _specific_stats.duplicate(true)
	var weapon_tags = stats_to_pass.get(&"tags", []) as Array[StringName]
	var damage_percent = float(stats_to_pass.get(&"weapon_damage_percentage", 1.0))

	# --- REFACTORED DAMAGE CALCULATION ---
	var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	stats_to_pass["final_damage_amount"] = final_damage * p_riposte_mult
	# --- END REFACTOR ---

	if is_initial_swing:
		stats_to_pass["parry_riposte_bonus_active"] = true

	if attack_instance.has_method("set_attack_properties"):
		attack_instance.set_attack_properties(final_direction, stats_to_pass, _owner_player_stats, _weapon_manager)
	
	return attack_instance

# This handler now updates the local state for this attack cycle
func _on_attack_hit_enemy(hit_count: int):
	if hit_count > 0:
		_specific_stats["parry_riposte_bonus_active"] = false
