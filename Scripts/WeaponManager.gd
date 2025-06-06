# WeaponManager.gd
# Final Version: Uses index-based logic for robust state changes and a 
# timer-based state machine for multi-spin attacks to avoid async/await.
class_name WeaponManager
extends Node

@export var max_weapons: int = 6
var active_weapons: Array[Dictionary] = [] 
var game_node_ref: Node 

var _whirlwind_timer: Timer
var _whirlwind_queue: Array[Dictionary] = [] 

signal weapon_added(weapon_data_dict: Dictionary) 
signal weapon_removed(weapon_id: StringName)
signal weapon_upgraded(weapon_id: StringName, new_level: int) 
signal active_weapons_changed() 

func _ready():
	_whirlwind_timer = Timer.new()
	_whirlwind_timer.name = "WhirlwindSpinTimer"
	_whirlwind_timer.one_shot = true 
	add_child(_whirlwind_timer)
	_whirlwind_timer.timeout.connect(Callable(self, "_on_whirlwind_spin_timer_timeout"))

	var tree_root = get_tree().root
	game_node_ref = tree_root.get_node_or_null("Game") 

func add_weapon_from_blueprint_id(weapon_id: StringName) -> bool:
	if not _ensure_game_node_ref(): return false
	var blueprint_resource = game_node_ref.get_weapon_blueprint_by_id(weapon_id)
	if is_instance_valid(blueprint_resource) and blueprint_resource is WeaponBlueprintData:
		return add_weapon(blueprint_resource)
	return false

func add_weapon(blueprint_data: WeaponBlueprintData) -> bool: 
	if not is_instance_valid(blueprint_data): return false
	if active_weapons.size() >= max_weapons: return false
	if _get_weapon_entry_index_by_id(blueprint_data.id) != -1: return false

	var cooldown_timer = Timer.new()
	cooldown_timer.name = str(blueprint_data.id) + "CooldownTimer"
	cooldown_timer.wait_time = blueprint_data.cooldown 
	cooldown_timer.one_shot = true 
	add_child(cooldown_timer) 

	var weapon_entry = {
		"id": blueprint_data.id,
		"title": blueprint_data.title,
		"cooldown_timer": cooldown_timer,
		"current_cooldown": blueprint_data.cooldown, 
		"weapon_level": 1,
		"specific_stats": blueprint_data.initial_specific_stats.duplicate(true), 
		"blueprint_resource": blueprint_data, 
		"acquired_upgrade_ids": [] 
	}
	active_weapons.append(weapon_entry)
	
	cooldown_timer.timeout.connect(Callable(self, "_trigger_temporary_child_attack").bind(blueprint_data.id))
	cooldown_timer.start()
	emit_signal("weapon_added", weapon_entry.duplicate(true))
	emit_signal("active_weapons_changed")
	return true

func _trigger_temporary_child_attack(weapon_id: StringName):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return

	var specific_stats = active_weapons[weapon_index].specific_stats
	
	var bonus_for_this_cycle = 0
	if specific_stats.get("has_reaping_momentum", false):
		bonus_for_this_cycle = specific_stats.get("reaping_momentum_bonus", 0)
		active_weapons[weapon_index].specific_stats["reaping_momentum_bonus"] = 0
	
	# Spawn the first spin
	_spawn_single_attack_instance(active_weapons[weapon_index], bonus_for_this_cycle) 
	
	var number_of_spins = 1
	if specific_stats.get("has_whirlwind", false):
		number_of_spins = int(specific_stats.get("whirlwind_count", 1))
	
	# If more spins are needed, queue them up
	if number_of_spins > 1:
		var spin_data = {
			"weapon_id": weapon_id,
			"spins_left": number_of_spins - 1,
			"delay": float(specific_stats.get("whirlwind_delay", 0.1)),
			"reaping_bonus_to_apply": bonus_for_this_cycle
		}
		_whirlwind_queue.append(spin_data)
		if _whirlwind_timer.is_stopped():
			_whirlwind_timer.wait_time = spin_data.delay
			_whirlwind_timer.start()
			
	_restart_weapon_cooldown(active_weapons[weapon_index])

func _on_whirlwind_spin_timer_timeout():
	if _whirlwind_queue.is_empty(): return

	var current_whirlwind = _whirlwind_queue.front()
	var weapon_index = _get_weapon_entry_index_by_id(current_whirlwind.weapon_id)
		
	if weapon_index != -1:
		_spawn_single_attack_instance(active_weapons[weapon_index], current_whirlwind.reaping_bonus_to_apply)
	
	current_whirlwind.spins_left -= 1
	if current_whirlwind.spins_left <= 0:
		_whirlwind_queue.pop_front()
	
	if not _whirlwind_queue.is_empty():
		var next_whirlwind = _whirlwind_queue.front()
		_whirlwind_timer.wait_time = next_whirlwind.delay
		_whirlwind_timer.start()

func _spawn_single_attack_instance(weapon_entry: Dictionary, p_reaping_bonus: int):
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	if not is_instance_valid(blueprint_data) or not is_instance_valid(blueprint_data.weapon_scene): return
	var weapon_instance = blueprint_data.weapon_scene.instantiate()
	if not is_instance_valid(weapon_instance): return
	
	var stats_for_this_instance = weapon_entry.specific_stats.duplicate(true)
	stats_for_this_instance["reaping_momentum_bonus_to_apply"] = p_reaping_bonus
	
	var owner_player = get_parent() as PlayerCharacter
	if is_instance_valid(owner_player):
		if blueprint_data.spawn_as_child:
			owner_player.add_child(weapon_instance); weapon_instance.global_position = owner_player.global_position 
		if weapon_instance.has_method("set_owner_player"):
			weapon_instance.set_owner_player(owner_player)
		if weapon_instance.has_method("set_weapon_manager_reference"):
			weapon_instance.set_weapon_manager_reference(self)
	else: get_tree().current_scene.add_child(weapon_instance)
	
	if weapon_instance.has_signal("reaping_momentum_hits"):
		weapon_instance.reaping_momentum_hits.connect(Callable(self, "_on_reaping_momentum_hits").bind(weapon_entry.id), CONNECT_ONE_SHOT)
	if weapon_instance.has_method("initialize_weapon_stats_and_attack"):
		weapon_instance.initialize_weapon_stats_and_attack(stats_for_this_instance)

func _on_reaping_momentum_hits(hit_count: int, weapon_id: StringName):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return
	
	var dmg_per_hit = int(active_weapons[weapon_index].specific_stats.get("reaping_momentum_dmg_per_hit", 1))
	var bonus_to_add = hit_count * dmg_per_hit 
	
	if bonus_to_add > 0:
		var current_stored_bonus = active_weapons[weapon_index].specific_stats.get("reaping_momentum_bonus", 0)
		active_weapons[weapon_index].specific_stats["reaping_momentum_bonus"] = current_stored_bonus + bonus_to_add

func _restart_weapon_cooldown(weapon_entry: Dictionary):
	if is_instance_valid(weapon_entry.get("cooldown_timer")):
		var timer = weapon_entry.cooldown_timer as Timer
		timer.wait_time = get_weapon_cooldown_value(weapon_entry)
		timer.start()

func get_weapon_cooldown_value(weapon_entry: Dictionary) -> float:
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	if not is_instance_valid(blueprint_data): return 999.0
	var final_cooldown = blueprint_data.cooldown
	var owner_player = get_parent() as PlayerCharacter 
	if is_instance_valid(owner_player) and is_instance_valid(owner_player.player_stats):
		var p_stats = owner_player.player_stats 
		if is_instance_valid(p_stats) and p_stats.has_method("get_current_global_cooldown_reduction_flat"): 
			final_cooldown -= p_stats.get_current_global_cooldown_reduction_flat()
			final_cooldown *= (1.0 - p_stats.get_current_global_cooldown_reduction_mult())
	final_cooldown *= (1.0 - float(weapon_entry.specific_stats.get("cooldown_reduction_percent", 0.0)))
	final_cooldown -= float(weapon_entry.specific_stats.get("cooldown_reduction_flat", 0.0))
	return max(0.05, final_cooldown) 

func apply_weapon_upgrade(weapon_id: StringName, upgrade_data_resource: WeaponUpgradeData):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: 
		print_debug("WARNING (WeaponManager): Weapon ID '", weapon_id, "' not found for upgrade.")
		return

	var current_stacks = active_weapons[weapon_index].acquired_upgrade_ids.count(upgrade_data_resource.upgrade_id)
	if upgrade_data_resource.max_stacks > 0 and current_stacks >= upgrade_data_resource.max_stacks: return

	for effect_resource in upgrade_data_resource.effects:
		if not is_instance_valid(effect_resource): continue
		
		if effect_resource is StatModificationEffectData:
			var stat_mod = effect_resource as StatModificationEffectData
			if stat_mod.target_scope == &"player_stats":
				var p_stats = get_parent().get_node_or_null("PlayerStats") as PlayerStats
				if is_instance_valid(p_stats) and p_stats.has_method("_process_stat_modification_effect"):
					p_stats._process_stat_modification_effect(stat_mod)
			elif stat_mod.target_scope == &"weapon_specific_stats":
				var key = stat_mod.stat_key; var value = stat_mod.get_value()
				var current_val = active_weapons[weapon_index].specific_stats.get(key, 0)
				active_weapons[weapon_index].specific_stats[key] = current_val + value
		
		elif effect_resource is CustomFlagEffectData:
			var flag_mod = effect_resource as CustomFlagEffectData
			if flag_mod.target_scope == &"weapon_specific_stats" or flag_mod.target_scope == &"weapon_behavior":
				active_weapons[weapon_index].specific_stats[flag_mod.flag_key] = flag_mod.flag_value
		
		elif effect_resource is StatusEffectApplicationData:
			var status_app_data = effect_resource as StatusEffectApplicationData
			if not active_weapons[weapon_index].specific_stats.has("on_hit_status_applications"):
				active_weapons[weapon_index].specific_stats["on_hit_status_applications"] = []
			active_weapons[weapon_index].specific_stats["on_hit_status_applications"].append(status_app_data)
	
	active_weapons[weapon_index].weapon_level += 1
	active_weapons[weapon_index].acquired_upgrade_ids.append(upgrade_data_resource.upgrade_id) 
	active_weapons[weapon_index].current_cooldown = get_weapon_cooldown_value(active_weapons[weapon_index])
	if is_instance_valid(active_weapons[weapon_index].cooldown_timer):
		active_weapons[weapon_index].cooldown_timer.wait_time = active_weapons[weapon_index].current_cooldown
	
	emit_signal("weapon_upgraded", weapon_id, active_weapons[weapon_index].weapon_level)
	emit_signal("active_weapons_changed")

func get_active_weapons_data_for_level_up() -> Array[Dictionary]:
	var weapons_data_copy: Array[Dictionary] = []
	for weapon_entry in active_weapons:
		var display_data = {
			"id": weapon_entry.id, "title": weapon_entry.title,
			"weapon_level": weapon_entry.weapon_level,
			"specific_stats": weapon_entry.specific_stats.duplicate(true), 
			"blueprint_resource_path": weapon_entry.blueprint_resource.resource_path if is_instance_valid(weapon_entry.blueprint_resource) else ""
		}
		weapons_data_copy.append(display_data)
	return weapons_data_copy

func _get_weapon_entry_index_by_id(weapon_id: StringName) -> int:
	for i in range(active_weapons.size()):
		if active_weapons[i].id == weapon_id:
			return i
	return -1

func _ensure_game_node_ref() -> bool:
	if is_instance_valid(game_node_ref) and game_node_ref.has_method("get_weapon_blueprint_by_id"):
		return true
	var tree_root = get_tree().root
	game_node_ref = tree_root.get_node_or_null("Game")
	if not is_instance_valid(game_node_ref) or not game_node_ref.has_method("get_weapon_blueprint_by_id"):
		print_debug("ERROR (WeaponManager @ _ensure_game_node_ref): game_node_ref issue.")
		return false
	return true
