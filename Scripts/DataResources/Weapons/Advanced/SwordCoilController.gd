# File: res://Scripts/Weapons/SwordCoilController.gd
# This controller is the main logic hub for the Sword Coil attack.
# It is spawned by the WeaponManager and handles spawning the visual sword,
# the main projectile, and any additional projectiles from upgrades.
# FIX: Centralized all spawning logic here to resolve argument mismatch errors.
# FIX: Controller now correctly manages its own lifetime to ensure all projectile timers can fire.

class_name SwordCoilController
extends Node2D

# Assign SwordCoil.tscn (the visual sword) and SwordCoilProjectile.tscn in the Inspector
@export var sword_visual_scene: PackedScene
@export var projectile_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager # Reference to call back for cooldown reduction

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager

	var owner_player = _owner_player_stats.get_parent()
	if not is_instance_valid(owner_player): queue_free(); return

	# --- Attack Speed Scaling ---
	var player_attack_speed_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	if player_attack_speed_mult <= 0: player_attack_speed_mult = 0.01

	# 1. Spawn the visual sword caster
	var sword_visual = sword_visual_scene.instantiate()
	owner_player.add_child(sword_visual)
	sword_visual.global_position = owner_player.global_position
	if sword_visual.has_method("set_attack_properties"):
		sword_visual.set_attack_properties(direction, _specific_stats, _owner_player_stats, _weapon_manager)

	# 2. Use a scaled timer to fire the main projectile from the sword's tip
	var fire_delay = 0.2 / player_attack_speed_mult # Assumes 0.2s is the fire point in the base animation
	get_tree().create_timer(fire_delay).timeout.connect(_fire_projectile.bind(direction, 1.0, sword_visual))

	# 3. Handle Blade Storm upgrade with a scaled timer
	var max_lifetime = fire_delay + 0.1 # Base lifetime for the controller
	if _specific_stats.get("has_blade_storm", false):
		var blade_storm_delay = float(_specific_stats.get("blade_storm_delay", 0.4)) / player_attack_speed_mult
		get_tree().create_timer(blade_storm_delay).timeout.connect(_fire_blade_storm_volley.bind(direction, sword_visual))
		max_lifetime = max(max_lifetime, blade_storm_delay + 0.1)
	
	# 4. The controller now deletes itself after the longest possible delay.
	get_tree().create_timer(max_lifetime, true, false, true).timeout.connect(queue_free)

func _fire_projectile(direction: Vector2, scale_multiplier: float, sword_visual: Node2D):
	# Failsafe checks
	if not is_instance_valid(sword_visual) or not is_instance_valid(projectile_scene): return
	var tip_node = sword_visual.get_node_or_null("Tip")
	if not is_instance_valid(tip_node):
		push_error("SwordCoilController: Could not find 'Tip' node on spawned sword visual.")
		return

	var projectile = projectile_scene.instantiate() as SwordCoilProjectile
	get_tree().current_scene.add_child(projectile)
	
	# Spawn from the tip's exact position and rotation
	projectile.global_transform = tip_node.global_transform
	
	# Prepare stats for this specific projectile
	var stats_for_projectile = _specific_stats.duplicate(true)
	stats_for_projectile["scale_multiplier"] = scale_multiplier
	
	# Call setup with all required arguments
	var owner_player = _owner_player_stats.get_parent()
	projectile.setup(direction, stats_for_projectile, _owner_player_stats, _weapon_manager, owner_player)
			
	# Connect the signal for Spell-Siphon
	if _specific_stats.get("has_spell_siphon", false):
		projectile.spell_siphon_hit.connect(_on_spell_siphon_proc)

func _fire_blade_storm_volley(base_direction: Vector2, sword_visual: Node2D):
	var angle_deg = float(_specific_stats.get("blade_storm_angle", 35.0))
	var angle_rad = deg_to_rad(angle_deg)
	
	# Fire the two side projectiles with a 50% size multiplier
	_fire_projectile(base_direction.rotated(angle_rad), 0.5, sword_visual)
	_fire_projectile(base_direction.rotated(-angle_rad), 0.5, sword_visual)

func _on_spell_siphon_proc():
	var chance = float(_specific_stats.get("spell_siphon_chance", 0.25))
	if randf() < chance:
		if is_instance_valid(_weapon_manager) and _weapon_manager.has_method("reduce_cooldown_for_weapon"):
			var reduction_amount = float(_specific_stats.get("spell_siphon_cooldown_reduction", 0.1))
			var weapon_id = _specific_stats.get("id")
			_weapon_manager.reduce_cooldown_for_weapon(weapon_id, reduction_amount)
