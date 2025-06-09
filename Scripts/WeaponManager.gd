# WeaponManager.gd
# This is the definitive, corrected version of the WeaponManager.
# It correctly differentiates between persistent summons and cooldown-based attacks,
# and restores the specific logic for Scythe upgrades.
class_name WeaponManager
extends Node

@export var max_weapons: int = 100
var active_weapons: Array[Dictionary] = [] 
var game_node_ref: Node 

# Timer and queue specifically for the Scythe's Whirlwind ability
var _whirlwind_timer: Timer
var _whirlwind_queue: Array[Dictionary] = [] 

# A dictionary to track active persistent summons by their weapon ID
var _active_summons: Dictionary = {}

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

# --- Core Weapon Handling ---

func add_weapon(blueprint_data: WeaponBlueprintData) -> bool: 
	if not is_instance_valid(blueprint_data): return false
	if active_weapons.size() >= max_weapons: return false
	if _get_weapon_entry_index_by_id(blueprint_data.id) != -1: return false

	var weapon_entry = {
		"id": blueprint_data.id,
		"title": blueprint_data.title,
		"weapon_level": 1,
		"specific_stats": blueprint_data.initial_specific_stats.duplicate(true), 
		"blueprint_resource": blueprint_data, 
		"acquired_upgrade_ids": [] 
	}
	
	# CORRECTED: Differentiated logic for summon types and other weapons
	if blueprint_data.tags.has("summon"):
		# This is for permanent summons like Moth Golem and Lesser Spirit that are spawned once.
		_spawn_persistent_summon(weapon_entry)
	else:
		# This handles all other attacks (Melee, Projectile, Orbital) that work on a cooldown.
		if blueprint_data.cooldown <= 0:
			print("ERROR (WeaponManager): Non-summon weapon '", blueprint_data.id, "' has a cooldown of 0 or less. It will not fire.")
		else:
			var cooldown_timer = Timer.new()
			cooldown_timer.name = str(blueprint_data.id) + "CooldownTimer"
			cooldown_timer.wait_time = blueprint_data.cooldown 
			cooldown_timer.one_shot = true 
			add_child(cooldown_timer)
			weapon_entry["cooldown_timer"] = cooldown_timer
			cooldown_timer.timeout.connect(Callable(self, "_on_attack_cooldown_finished").bind(blueprint_data.id))
			cooldown_timer.start()

	active_weapons.append(weapon_entry)
	emit_signal("weapon_added", weapon_entry.duplicate(true))
	emit_signal("active_weapons_changed")
	return true

func _on_attack_cooldown_finished(weapon_id: StringName):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return
	
	var weapon_entry = active_weapons[weapon_index]
	var specific_stats = weapon_entry.specific_stats
	
	# RESTORED: Scythe-specific logic from the original working script
	var reaping_bonus = int(specific_stats.get("reaping_momentum_bonus", 0))
	_spawn_attack_instance(weapon_entry, reaping_bonus)
	
	var number_of_spins = 1
	if specific_stats.get("has_whirlwind", false):
		number_of_spins = int(specific_stats.get("whirlwind_count", 1))
	
	if number_of_spins > 1:
		var spin_data = { "weapon_id": weapon_id, "spins_left": number_of_spins - 1, "delay": float(specific_stats.get("whirlwind_delay", 0.1)), "reaping_bonus_to_apply": reaping_bonus }
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
		# Spawn the whirlwind attack with the same reaping bonus as the initial hit
		_spawn_attack_instance(active_weapons[weapon_index], current_whirlwind.reaping_bonus_to_apply)
	
	current_whirlwind.spins_left -= 1
	if current_whirlwind.spins_left <= 0: _whirlwind_queue.pop_front()
	
	if not _whirlwind_queue.is_empty():
		var next_whirlwind = _whirlwind_queue.front()
		_whirlwind_timer.wait_time = next_whirlwind.delay
		_whirlwind_timer.start()

func _spawn_attack_instance(weapon_entry: Dictionary, p_reaping_bonus: int):
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	if not is_instance_valid(blueprint_data) or not is_instance_valid(blueprint_data.weapon_scene): return
	
	var owner_player = get_parent() as PlayerCharacter
	if not is_instance_valid(owner_player): return

	var direction = Vector2.ZERO
	var spawn_position = owner_player.global_position
	var target_found = true

	if blueprint_data.requires_direction:
		match blueprint_data.targeting_type:
			"nearest_enemy":
				var nearest_enemy = owner_player._find_nearest_enemy()
				if is_instance_valid(nearest_enemy):
					direction = (nearest_enemy.global_position - owner_player.global_position).normalized()
				else:
					target_found = false
			"mouse_location":
				var world_mouse_pos = owner_player.get_global_mouse_position()
				direction = (world_mouse_pos - owner_player.global_position).normalized()
				var max_range = float(weapon_entry.specific_stats.get("max_cast_range", 300.0))
				if owner_player.global_position.distance_to(world_mouse_pos) > max_range:
					spawn_position = owner_player.global_position + direction * max_range
				else:
					spawn_position = world_mouse_pos
			"mouse":
				if is_instance_valid(owner_player.melee_aiming_dot):
					direction = owner_player.melee_aiming_dot.get_aiming_direction()
	
	if not target_found: return

	var weapon_instance = blueprint_data.weapon_scene.instantiate()
	if not is_instance_valid(weapon_instance): return
	
	var stats_for_this_instance = weapon_entry.specific_stats.duplicate(true)
	stats_for_this_instance["base_lifetime"] = blueprint_data.base_lifetime
	
	if p_reaping_bonus > 0:
		stats_for_this_instance["reaping_momentum_bonus_to_apply"] = p_reaping_bonus
		weapon_entry.specific_stats["reaping_momentum_bonus"] = 0
	
	if blueprint_data.tags.has("centered_melee"):
		owner_player.add_child(weapon_instance)
		weapon_instance.position = Vector2.ZERO
	elif blueprint_data.tags.has("melee"):
		owner_player.add_child(weapon_instance)
		weapon_instance.position = owner_player.melee_aiming_dot.position
	else: 
		var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
		if is_instance_valid(attacks_container): attacks_container.add_child(weapon_instance)
		else: get_tree().current_scene.add_child(weapon_instance)
		weapon_instance.global_position = spawn_position
	
	if weapon_instance.has_method("set_attack_properties"):
		weapon_instance.set_attack_properties(direction, stats_for_this_instance, owner_player.player_stats)
	
	if weapon_instance.has_signal("reaping_momentum_hits"):
		weapon_instance.reaping_momentum_hits.connect(Callable(self, "_on_reaping_momentum_hits").bind(weapon_entry.id), CONNECT_ONE_SHOT)

func _spawn_persistent_summon(weapon_entry: Dictionary):
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	var owner_player = get_parent() as PlayerCharacter
	if not is_instance_valid(blueprint_data) or not is_instance_valid(owner_player): return

	var summon_instance = blueprint_data.weapon_scene.instantiate()
	if not is_instance_valid(summon_instance): return
	
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container): attacks_container.add_child(summon_instance)
	else: get_tree().current_scene.add_child(summon_instance)
	
	summon_instance.global_position = owner_player.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	
	if summon_instance.has_method("initialize"):
		var stats_to_pass = weapon_entry.specific_stats.duplicate(true)
		stats_to_pass["weapon_level"] = weapon_entry.weapon_level
		summon_instance.initialize(owner_player, stats_to_pass)
	
	if not _active_summons.has(blueprint_data.id):
		_active_summons[blueprint_data.id] = []
	_active_summons[blueprint_data.id].append(summon_instance)
	
	summon_instance.tree_exiting.connect(_on_summon_destroyed.bind(blueprint_data.id, summon_instance))


# --- Upgrade & Helper Functions ---

func apply_weapon_upgrade(weapon_id: StringName, upgrade_data_resource: WeaponUpgradeData):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return

	var weapon_entry = active_weapons[weapon_index]
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData

	var current_stacks = weapon_entry.acquired_upgrade_ids.count(upgrade_data_resource.upgrade_id)
	if upgrade_data_resource.max_stacks > 0 and current_stacks >= upgrade_data_resource.max_stacks: return
	
	for effect_resource in upgrade_data_resource.effects:
		if not is_instance_valid(effect_resource): continue
		
		if effect_resource is StatModificationEffectData:
			var stat_mod = effect_resource as StatModificationEffectData
			if stat_mod.target_scope == &"player_stats":
				var p_stats = get_parent().player_stats
				if is_instance_valid(p_stats):
					p_stats._process_stat_modification_effect(stat_mod)
			elif stat_mod.target_scope == &"weapon_specific_stats":
				var key = stat_mod.stat_key
				var value = stat_mod.get_value()
				var current_val = weapon_entry.specific_stats.get(key, 0.0)
				weapon_entry.specific_stats[key] = current_val + value
		
		elif effect_resource is CustomFlagEffectData:
			var flag_mod = effect_resource as CustomFlagEffectData
			if flag_mod.target_scope == &"weapon_specific_stats" or flag_mod.target_scope == &"weapon_behavior":
				weapon_entry.specific_stats[flag_mod.flag_key] = flag_mod.flag_value
		
		elif effect_resource is StatusEffectApplicationData:
			var status_app_data = effect_resource as StatusEffectApplicationData
			if not weapon_entry.specific_stats.has("on_hit_status_applications"):
				weapon_entry.specific_stats["on_hit_status_applications"] = []
			weapon_entry.specific_stats["on_hit_status_applications"].append(status_app_data)
	
	weapon_entry.weapon_level += 1
	weapon_entry.acquired_upgrade_ids.append(upgrade_data_resource.upgrade_id)
	
	if blueprint_data.tags.has("summon"):
		var max_summons = int(weapon_entry.specific_stats.get("max_summons_of_type", 1))
		var current_summon_count = _active_summons.get(weapon_id, []).size()
		if max_summons > current_summon_count:
			for i in range(max_summons - current_summon_count):
				_spawn_persistent_summon(weapon_entry)
		
		var owner_player = get_parent() as PlayerCharacter
		if _active_summons.has(weapon_id) and is_instance_valid(owner_player):
			for summon_instance in _active_summons[weapon_id]:
				if is_instance_valid(summon_instance) and summon_instance.has_method("update_stats"):
					var stats_to_pass = weapon_entry.specific_stats.duplicate(true)
					stats_to_pass["weapon_level"] = weapon_entry.weapon_level
					summon_instance.update_stats(stats_to_pass)
	
	var owner_player = get_parent() as PlayerCharacter
	if is_instance_valid(owner_player) and owner_player.has_method("increment_basic_class_level"):
		if not blueprint_data.class_tag_restrictions.is_empty():
			var class_enum_to_increment = blueprint_data.class_tag_restrictions[0]
			owner_player.increment_basic_class_level(class_enum_to_increment)

	emit_signal("weapon_upgraded", weapon_id, weapon_entry.weapon_level)
	emit_signal("active_weapons_changed")


func _on_reaping_momentum_hits(hit_count: int, weapon_id: StringName):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return
	
	var weapon_entry = active_weapons[weapon_index]
	var dmg_per_hit = int(weapon_entry.specific_stats.get("reaping_momentum_dmg_per_hit", 1))
	var bonus_to_add = hit_count * dmg_per_hit 
	
	if bonus_to_add > 0:
		var current_stored_bonus = weapon_entry.specific_stats.get("reaping_momentum_bonus", 0)
		weapon_entry.specific_stats["reaping_momentum_bonus"] = current_stored_bonus + bonus_to_add

func _on_summon_destroyed(weapon_id: StringName, summon_instance: Node):
	if _active_summons.has(weapon_id):
		if _active_summons[weapon_id].has(summon_instance):
			_active_summons[weapon_id].erase(summon_instance)

func _restart_weapon_cooldown(weapon_entry: Dictionary):
	var timer = weapon_entry.get("cooldown_timer") as Timer
	if is_instance_valid(timer):
		timer.wait_time = get_weapon_cooldown_value(weapon_entry)
		timer.start()

func get_weapon_cooldown_value(weapon_entry: Dictionary) -> float:
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	if not is_instance_valid(blueprint_data): return 999.0
	
	var final_cooldown = blueprint_data.cooldown
	var owner_player = get_parent() as PlayerCharacter 
	if is_instance_valid(owner_player) and is_instance_valid(owner_player.player_stats):
		var p_stats = owner_player.player_stats 
		if p_stats.has_method("get_current_attack_speed_multiplier"): 
			var atk_speed_mult = p_stats.get_current_attack_speed_multiplier()
			if atk_speed_mult > 0:
				final_cooldown /= atk_speed_mult
	
	return max(0.05, final_cooldown) 

func get_active_weapons_data_for_level_up() -> Array[Dictionary]:
	var weapons_data_copy: Array[Dictionary] = []
	for weapon_entry in active_weapons:
		var display_data = {
			"id": weapon_entry.id,
			"title": weapon_entry.title,
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
	game_node_ref = get_tree().root.get_node_or_null("Game")
	return is_instance_valid(game_node_ref)
