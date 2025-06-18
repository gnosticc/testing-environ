# ======================================================================
# 3. MODIFIED SCRIPT: DaggerStrikeController.gd
# Path: res://Scripts/Weapons/DaggerStrikeController.gd
# FIX: Refactored lifetime management to be immune to attack speed changes.
# It now calculates the true total duration of the combo and uses a single
# master timer to destroy itself, guaranteeing all hits can spawn.
# ======================================================================

class_name DaggerStrikeController
extends Node2D

@export var hitbox_scene: PackedScene
@export var fan_of_knives_scene: PackedScene
@export var proc_visual_effect_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _base_direction: Vector2
var _attack_sequence: Array

var _hit_tracker: Dictionary = {}
var _damage_tracker: Dictionary = {}
var _has_thousand_cuts: bool = false

const FAN_OF_KNIVES_SCENE_PATH = "res://Scenes/Weapons/Projectiles/FanOfKnivesController.tscn"

func _ready():
	if fan_of_knives_scene == null and ResourceLoader.exists(FAN_OF_KNIVES_SCENE_PATH):
		fan_of_knives_scene = load(FAN_OF_KNIVES_SCENE_PATH)

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_attack_stats.duplicate(true)
	_owner_player_stats = p_player_stats
	_base_direction = direction.normalized() if direction.length_squared() > 0 else Vector2.RIGHT
	_attack_sequence = _specific_stats.get(&"attack_sequence", [])
	_has_thousand_cuts = _specific_stats.get(&"has_thousand_cuts", false)

	if not is_instance_valid(hitbox_scene) or _attack_sequence.is_empty():
		push_error("DaggerStrikeController: Missing hitbox scene or attack sequence."); queue_free(); return
	
	# Execute the sequence of attacks
	_execute_attack_sequence()
	
	# Calculate the true total duration of the entire attack combo
	var total_duration = 0.0
	var base_attack_duration = float(_specific_stats.get(&"base_attack_duration", 0.25))
	var player_attack_speed_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	var weapon_attack_speed_mod = float(_specific_stats.get(&"weapon_attack_speed_mod", 1.0))
	var final_attack_speed_multiplier = player_attack_speed_multiplier * weapon_attack_speed_mod
	if final_attack_speed_multiplier <= 0: final_attack_speed_multiplier = 0.01
	var actual_slash_duration = base_attack_duration / final_attack_speed_multiplier

	for hit_data in _attack_sequence:
		total_duration += float(hit_data.get("delay", 0.0))
	
	# The controller's lifetime is the sum of all delays plus the duration of the final slash animation.
	get_tree().create_timer(total_duration + actual_slash_duration + 0.1, false).timeout.connect(queue_free)

func _execute_attack_sequence():
	var cumulative_delay = 0.0
	for i in range(_attack_sequence.size()):
		var hit_data = _attack_sequence[i]
		cumulative_delay += float(hit_data.get("delay", 0.0))
		
		# Use a timer to spawn each hit after its cumulative delay.
		var timer = get_tree().create_timer(cumulative_delay, true, false, true)
		timer.timeout.connect(_spawn_hitbox.bind(i))

func _spawn_hitbox(hit_index: int):
	if not is_instance_valid(self): return # Controller might have been freed by other means
	var hit_data = _attack_sequence[hit_index]
	var owner_player = _owner_player_stats.get_parent()
	if not is_instance_valid(owner_player): return

	var hitbox_instance = hitbox_scene.instantiate() as DaggerStrikeAttack

	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container): attacks_container.add_child(hitbox_instance)
	else: get_tree().current_scene.add_child(hitbox_instance)

	var rotation_offset = deg_to_rad(float(hit_data.get(&"rotation_offset", 0.0)))
	var final_direction = _base_direction.rotated(rotation_offset)
	if is_instance_valid(owner_player.melee_aiming_dot):
		hitbox_instance.global_position = owner_player.melee_aiming_dot.global_position
	else:
		hitbox_instance.global_position = owner_player.global_position
	
	var hit_specific_stats = _specific_stats.duplicate(true)
	hit_specific_stats["damage_multiplier"] = float(hit_data.get(&"damage_multiplier", 1.0))
	if hit_data.get("is_finishing_blow", false):
		hit_specific_stats["is_finishing_blow_visual"] = true

	if is_instance_valid(hitbox_scene):
		hit_specific_stats["scene_file_path"] = hitbox_scene.resource_path
		
	hitbox_instance.set_attack_properties(final_direction, hit_specific_stats, _owner_player_stats)

	if _has_thousand_cuts:
		hitbox_instance.hit_enemy_for_combo.connect(_on_dagger_hit_enemy_for_combo.bind(hit_index))
		hitbox_instance.dealt_damage.connect(_on_dagger_dealt_damage)

	if hit_index == _attack_sequence.size() - 1 and _specific_stats.get(&"has_fan_of_knives", false):
		if not is_instance_valid(fan_of_knives_scene):
			push_error("DaggerStrikeController: Fan of Knives scene not loaded!")
			return
		
		var fok_instance = fan_of_knives_scene.instantiate()
		add_child(fok_instance)
		fok_instance.global_position = owner_player.global_position
		
		var final_slash_damage = _owner_player_stats.get_calculated_player_damage(
			hit_specific_stats.get(&"weapon_damage_percentage", 1.0) * hit_specific_stats["damage_multiplier"],
			hit_specific_stats.get("tags", [])
		)
		
		if fok_instance.has_method("initialize"):
			fok_instance.initialize(int(round(final_slash_damage)), _owner_player_stats)

func _on_dagger_dealt_damage(enemy_node: Node, damage_dealt: int):
	if not _is_target_valid_for_combo(enemy_node): return
	var current_total = _damage_tracker.get(enemy_node, 0)
	_damage_tracker[enemy_node] = current_total + damage_dealt

func _on_dagger_hit_enemy_for_combo(enemy_node: Node, hit_index: int):
	if not _is_target_valid_for_combo(enemy_node): return

	var hit_bit = 1 << hit_index
	var current_mask = _hit_tracker.get(enemy_node, 0)
	_hit_tracker[enemy_node] = current_mask | hit_bit
	
	var required_mask = (1 << _attack_sequence.size()) - 1
	if _hit_tracker[enemy_node] == required_mask:
		print_debug("THOUSAND CUTS PROC on ", enemy_node.name)
		
		var total_accumulated_damage = _damage_tracker.get(enemy_node, 0)
		var owner_player = _owner_player_stats.get_parent()

		if enemy_node.has_method("take_damage") and total_accumulated_damage > 0:
			var attack_stats_for_bonus_damage: Dictionary = {
				PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
			}
			enemy_node.take_damage(total_accumulated_damage, owner_player, attack_stats_for_bonus_damage)
			
			if is_instance_valid(proc_visual_effect_scene):
				var proc_vfx = proc_visual_effect_scene.instantiate()
				get_tree().current_scene.add_child(proc_vfx)
				proc_vfx.global_position = enemy_node.global_position
				if proc_vfx.has_method("detonate"):
					proc_vfx.detonate(0, 40, owner_player, {})
		
		_hit_tracker.erase(enemy_node)
		_damage_tracker.erase(enemy_node)

func _is_target_valid_for_combo(target: Node) -> bool:
	return is_instance_valid(target) and target is BaseEnemy and not target.is_dead()
