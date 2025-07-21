# File: Scripts/Weapons/Advanced/WarhammerController.gd
# No changes are needed in this file. The logic for spawning the
# hit effect by adding it to the scene and then initializing it is correct.

class_name WarhammerController
extends Node2D

@export var attack_scene: PackedScene
@export var cataclysmic_slam_vfx_scene: PackedScene
@export var cataclysm_hit_effect_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager # Reference to call back for cooldown reduction

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = _p_weapon_manager

	var shot_counter = int(_specific_stats.get("shot_counter", 0))
	var has_slam = _specific_stats.get(&"has_cataclysmic_slam", false)

	_execute_normal_swing(direction)
	
	if has_slam and shot_counter >= 5:
		_execute_cataclysmic_slam()
		
		var player_node = get_parent()
		if is_instance_valid(player_node):
			var owner_weapon_manager = player_node.get_node_or_null("WeaponManager")
			if is_instance_valid(owner_weapon_manager) and owner_weapon_manager.has_method("reset_weapon_shot_counter"):
				owner_weapon_manager.reset_weapon_shot_counter(_specific_stats.get("id"))
			else:
				push_error("WarhammerController: Could not get WeaponManager node from parent or it's missing the reset method.")
		else:
			push_error("WarhammerController: Parent node is invalid. Cannot find WeaponManager.")
		
	get_tree().create_timer(0.1, false, true).timeout.connect(queue_free)

func _execute_normal_swing(direction: Vector2):
	if not is_instance_valid(attack_scene):
		push_error("WarhammerController: Attack Scene is not assigned!"); return
	
	var attack_instance = attack_scene.instantiate()
	var owner_player = _owner_player_stats.get_parent()
	
	owner_player.add_child(attack_instance)
	attack_instance.global_position = owner_player.global_position
	
	attack_instance.set_attack_properties(direction, _specific_stats, _owner_player_stats, _weapon_manager)

func _execute_cataclysmic_slam():
	var owner_player = _owner_player_stats.get_parent()
	if not is_instance_valid(owner_player): return

	if is_instance_valid(cataclysmic_slam_vfx_scene):
		var vfx = cataclysmic_slam_vfx_scene.instantiate()
		owner_player.add_child(vfx)
		vfx.global_position = owner_player.global_position

	var damage_mult = float(_specific_stats.get("cataclysmic_slam_damage_mult", 2.0))
	var knockback = float(_specific_stats.get("cataclysmic_slam_knockback", 400.0))
	
	var weapon_damage_percent = float(_specific_stats.get(&"weapon_damage_percentage", 1.0))
	var final_damage_percent = weapon_damage_percent * damage_mult
	
	# --- REFACTORED DAMAGE CALCULATION ---
	var weapon_tags = _specific_stats.get("tags", []) as Array[StringName]
	# Step 1: Get the base damage.
	var base_damage = _owner_player_stats.get_calculated_base_damage(final_damage_percent)
	# Step 2: Apply tag-specific multipliers to get the final damage.
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	var slam_damage = int(round(final_damage))
	# --- END REFACTOR ---
	
	var slam_radius = float(_specific_stats.get("cataclysmic_slam_radius", 250.0))
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new(); query.shape.radius = slam_radius
	query.transform = owner_player.global_transform
	query.collision_mask = 8
	
	var results = space_state.intersect_shape(query)
	for result in results:
		var enemy = result.get("collider")
		if enemy is BaseEnemy and is_instance_valid(enemy) and not enemy.is_dead():
			# The weapon_tags variable is already defined above.
			enemy.take_damage(slam_damage, owner_player, {}, weapon_tags)
			var kb_dir = (enemy.global_position - owner_player.global_position).normalized()
			if kb_dir == Vector2.ZERO: kb_dir = Vector2.RIGHT.rotated(randf_range(0, TAU))
			enemy.apply_knockback(kb_dir, knockback)
			
			if is_instance_valid(cataclysm_hit_effect_scene):
				var hit_vfx = cataclysm_hit_effect_scene.instantiate()
				
				get_tree().current_scene.add_child(hit_vfx)
				hit_vfx.global_position = enemy.global_position
				
				if hit_vfx.has_method("initialize"):
					hit_vfx.initialize(enemy)
				else:
					push_warning("CataclysmHitEffect is missing initialize() method.")
