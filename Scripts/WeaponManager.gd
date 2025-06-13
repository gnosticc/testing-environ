# WeaponManager.gd
# This version adds logic to automatically set an "acquired" flag
# based on the `set_acquired_flag_on_weapon` property in WeaponUpgradeData.

class_name WeaponManager
extends Node

@export var max_weapons: int = 100
var active_weapons: Array[Dictionary] = []
var game_node_ref: Node

# --- Scythe-Specific Mechanics ---
var _whirlwind_timer: Timer
var _whirlwind_queue: Array[Dictionary] = []

# --- Summon Tracking ---
var _active_summons: Dictionary = {}

# --- Signals ---
signal weapon_added(weapon_data_dict: Dictionary)
signal weapon_removed(weapon_id: StringName)
signal weapon_upgraded(weapon_id: StringName, new_level: int)
signal active_weapons_changed()

func _ready():
	_whirlwind_timer = Timer.new()
	_whirlwind_timer.name = "WhirlwindSpinTimer"
	_whirlwind_timer.one_shot = true
	add_child(_whirlwind_timer)
	_whirlwind_timer.timeout.connect(_on_whirlwind_spin_timer_timeout)
	game_node_ref = get_tree().root.get_node_or_null("Game")

func add_weapon(blueprint_data: WeaponBlueprintData) -> bool:
	if not is_instance_valid(blueprint_data) or active_weapons.size() >= max_weapons or _get_weapon_entry_index_by_id(blueprint_data.id) != -1:
		return false

	var weapon_entry = {
		"id": blueprint_data.id, "title": blueprint_data.title, "weapon_level": 1,
		"blueprint_resource": blueprint_data, "acquired_upgrade_ids": [],
		"tags": blueprint_data.tags.duplicate(true),
		"specific_stats": blueprint_data.initial_specific_stats.duplicate(true),
		"_flat_mods": {}, "_percent_add_mods": {}, "_percent_mult_final_mods": {}
	}
	for key_enum_value in PlayerStatKeys.Keys.values():
		var key_string: StringName = PlayerStatKeys.KEY_NAMES[key_enum_value]
		weapon_entry._flat_mods[key_string] = 0.0
		weapon_entry._percent_add_mods[key_string] = 0.0
		weapon_entry._percent_mult_final_mods[key_string] = 1.0

	if blueprint_data.tags.has("summon"):
		_spawn_persistent_summon(weapon_entry)
	else:
		if blueprint_data.cooldown <= 0: return false
		var cooldown_timer = Timer.new()
		cooldown_timer.name = str(blueprint_data.id) + "CooldownTimer"
		cooldown_timer.wait_time = get_weapon_cooldown_value(weapon_entry)
		cooldown_timer.one_shot = true
		add_child(cooldown_timer)
		weapon_entry["cooldown_timer"] = cooldown_timer
		cooldown_timer.timeout.connect(_on_attack_cooldown_finished.bind(blueprint_data.id))
		cooldown_timer.start()

	active_weapons.append(weapon_entry)
	emit_signal("weapon_added", weapon_entry.duplicate(true))
	emit_signal("active_weapons_changed")
	return true

func _on_attack_cooldown_finished(weapon_id: StringName):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return

	var weapon_entry = active_weapons[weapon_index]
	var reaping_bonus = int(weapon_entry.specific_stats.get(&"reaping_momentum_accumulated_bonus", 0))

	# DEBUG: Print the bonus that has been accumulated BEFORE this new swing.
	print_debug("WeaponManager: Starting new swing for '", weapon_id, "' with Reaping Bonus: ", reaping_bonus)

	# The first swing of the attack cycle is spawned here. We pass true for `is_initial_swing`.
	_spawn_attack_instance(weapon_entry, reaping_bonus, true)

	if weapon_entry.specific_stats.get(&"has_whirlwind", false):
		var number_of_spins = int(_calculate_final_weapon_stat(weapon_entry, &"whirlwind_count"))
		if number_of_spins > 1:
			var spin_delay = float(_calculate_final_weapon_stat(weapon_entry, &"whirlwind_delay"))
			# Subsequent spins are queued. They are NOT the initial swing.
			var spin_data = { "weapon_id": weapon_id, "spins_left": number_of_spins - 1, "delay": spin_delay, "reaping_bonus_to_apply": reaping_bonus, "is_initial_swing": false }
			_whirlwind_queue.append(spin_data)
			if _whirlwind_timer.is_stopped():
				_whirlwind_timer.wait_time = spin_data.delay
				_whirlwind_timer.start()

	_restart_weapon_cooldown(weapon_entry)

func _on_whirlwind_spin_timer_timeout():
	if _whirlwind_queue.is_empty(): return
	var current_whirlwind = _whirlwind_queue.front()
	var weapon_index = _get_weapon_entry_index_by_id(current_whirlwind.weapon_id)
	if weapon_index != -1:
		# Spawn the next whirlwind slash. This is NOT the initial swing.
		_spawn_attack_instance(active_weapons[weapon_index], current_whirlwind.reaping_bonus_to_apply, false)
	current_whirlwind.spins_left -= 1
	if current_whirlwind.spins_left <= 0:
		_whirlwind_queue.pop_front()
	if not _whirlwind_queue.is_empty():
		var next_whirlwind = _whirlwind_queue.front()
		_whirlwind_timer.wait_time = next_whirlwind.delay
		_whirlwind_timer.start()

func _spawn_attack_instance(weapon_entry: Dictionary, p_reaping_bonus: int = 0, is_initial_swing: bool = false):
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	var owner_player = get_parent() as PlayerCharacter
	if not is_instance_valid(blueprint_data) or not is_instance_valid(owner_player): return
	
	var direction = Vector2.ZERO
	var spawn_position = owner_player.global_position
	var target_found: bool = true

	if blueprint_data.requires_direction:
		match blueprint_data.targeting_type:
			&"nearest_enemy":
				var nearest_enemy = owner_player._find_nearest_enemy()
				if is_instance_valid(nearest_enemy):
					direction = (nearest_enemy.global_position - owner_player.global_position).normalized()
				else:
					target_found = false
			&"mouse_location":
				var world_mouse_pos = owner_player.get_global_mouse_position()
				direction = (world_mouse_pos - owner_player.global_position).normalized()
				var max_range = float(_calculate_final_weapon_stat(weapon_entry, PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAX_CAST_RANGE]))
				max_range += owner_player.player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_MAX_RANGE_ADD)
				spawn_position = owner_player.global_position.move_toward(world_mouse_pos, max_range)
			&"mouse_direction":
				if is_instance_valid(owner_player.melee_aiming_dot) and owner_player.melee_aiming_dot.has_method("get_aiming_direction"):
					direction = owner_player.melee_aiming_dot.get_aiming_direction()
				else:
					push_warning("WeaponManager: Melee aiming dot or its 'get_aiming_direction' method is invalid. Falling back to mouse.")
					direction = (owner_player.get_global_mouse_position() - owner_player.global_position).normalized()
					if direction == Vector2.ZERO: direction = Vector2.RIGHT
	
	if not target_found: return

	var weapon_instance = blueprint_data.weapon_scene.instantiate()
	if not is_instance_valid(weapon_instance):
		push_error("WeaponManager: Failed to instantiate weapon scene for '", blueprint_data.id, "'."); return
	
	if blueprint_data.tags.has("centered_melee"):
		owner_player.add_child(weapon_instance)
		weapon_instance.position = Vector2.ZERO
	elif blueprint_data.tags.has("melee"):
		owner_player.add_child(weapon_instance)
		if is_instance_valid(owner_player.melee_aiming_dot):
			weapon_instance.position = owner_player.melee_aiming_dot.position
		else:
			weapon_instance.position = Vector2.ZERO
	else:
		var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
		var parent_node = attacks_container if is_instance_valid(attacks_container) else get_tree().current_scene
		parent_node.add_child(weapon_instance)
		weapon_instance.global_position = spawn_position

	var calculated_stats = {}
	for key in weapon_entry.specific_stats.keys():
		var value = weapon_entry.specific_stats[key]
		if value is int or value is float: calculated_stats[key] = _calculate_final_weapon_stat(weapon_entry, key)
		elif value is Array or value is Dictionary: calculated_stats[key] = value.duplicate(true)
		else: calculated_stats[key] = value
	calculated_stats["tags"] = weapon_entry.tags.duplicate(true)

	# Pass and then reset the Reaping Momentum bonus
	calculated_stats[&"reaping_momentum_accumulated_bonus"] = p_reaping_bonus
	weapon_entry.specific_stats[&"reaping_momentum_accumulated_bonus"] = 0

	if weapon_instance.has_method("set_attack_properties"):
		weapon_instance.set_attack_properties(direction, calculated_stats, owner_player.player_stats)
	# Removed CONNECT_ONE_SHOT. The manager will now listen for every hit signal
	# from this attack instance until the instance is destroyed.
	if weapon_instance.has_signal("reaping_momentum_hit"):
		weapon_instance.reaping_momentum_hit.connect(_on_reaping_momentum_hit.bind(weapon_entry.id))

func _on_reaping_momentum_hit(hit_count: int, weapon_id: StringName):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return
	var weapon_entry = active_weapons[weapon_index]
	var dmg_per_hit = int(_calculate_final_weapon_stat(weapon_entry, &"reaping_momentum_damage_per_hit"))
	var current_bonus = weapon_entry.specific_stats.get(&"reaping_momentum_accumulated_bonus", 0)
	weapon_entry.specific_stats[&"reaping_momentum_accumulated_bonus"] = current_bonus + (hit_count * dmg_per_hit)
	
	print_debug("WeaponManager: Reaping Momentum hit received. New accumulated bonus: ", weapon_entry.specific_stats[&"reaping_momentum_accumulated_bonus"])


func _spawn_persistent_summon(weapon_entry: Dictionary):
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	var owner_player = get_parent() as PlayerCharacter
	if not is_instance_valid(blueprint_data) or not is_instance_valid(owner_player): return

	var base_max_summons = int(_calculate_final_weapon_stat(weapon_entry, PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAX_SUMMONS_OF_TYPE]))
	var global_summon_add = int(owner_player.player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_COUNT_ADD))
	var final_max_summons = base_max_summons + global_summon_add
	
	if not _active_summons.has(blueprint_data.id): _active_summons[blueprint_data.id] = []
	else: _active_summons[blueprint_data.id] = _active_summons[blueprint_data.id].filter(func(s): return is_instance_valid(s))

	if _active_summons[blueprint_data.id].size() >= final_max_summons: return

	var summon_instance = blueprint_data.weapon_scene.instantiate()
	if not is_instance_valid(summon_instance): return

	get_tree().current_scene.add_child(summon_instance)
	summon_instance.global_position = owner_player.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	
	var calculated_summon_stats = {}
	var p_stats = owner_player.player_stats
	
	for key in weapon_entry.specific_stats.keys():
		var value = weapon_entry.specific_stats[key]
		if value is int or value is float:
			calculated_summon_stats[key] = _calculate_final_weapon_stat(weapon_entry, key)
		else:
			calculated_summon_stats[key] = value.duplicate(true)
	
	calculated_summon_stats[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE]] *= p_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_DAMAGE_MULTIPLIER)
	calculated_summon_stats[&"base_lifetime"] = blueprint_data.base_lifetime * p_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_LIFETIME_MULTIPLIER)
	calculated_summon_stats[&"weapon_id"] = weapon_entry.id
	calculated_summon_stats[&"tags"] = weapon_entry.tags.duplicate(true)

	if summon_instance.has_signal("instances_spawned"):
		if not summon_instance.is_connected("instances_spawned", _on_lesser_spirit_controller_instances_spawned):
			summon_instance.instances_spawned.connect(_on_lesser_spirit_controller_instances_spawned, CONNECT_ONE_SHOT)
	else:
		_active_summons[blueprint_data.id].append(summon_instance)
		summon_instance.tree_exiting.connect(_on_summon_destroyed.bind(blueprint_data.id, summon_instance))
	
	if summon_instance.has_method("set_attack_properties"):
		(summon_instance as Node2D).set_attack_properties(Vector2.ZERO, calculated_summon_stats, p_stats)
	else:
		push_warning("WeaponManager: Summon instance '", blueprint_data.id, "' missing set_attack_properties method.")

func _on_lesser_spirit_controller_instances_spawned(summon_weapon_id: StringName, spawned_instances: Array[Node2D]):
	if not _active_summons.has(summon_weapon_id): _active_summons[summon_weapon_id] = []
	for instance in spawned_instances:
		if is_instance_valid(instance):
			_active_summons[summon_weapon_id].append(instance)
			if not instance.is_connected("tree_exiting", Callable(self, "_on_summon_destroyed").bind(summon_weapon_id, instance)):
				instance.tree_exiting.connect(_on_summon_destroyed.bind(summon_weapon_id, instance))

func _on_summon_destroyed(weapon_id: StringName, summon_instance: Node):
	if _active_summons.has(weapon_id) and _active_summons[weapon_id].has(summon_instance):
		_active_summons[weapon_id].erase(summon_instance)

func _restart_weapon_cooldown(weapon_entry: Dictionary):
	var timer = weapon_entry.get("cooldown_timer") as Timer
	if is_instance_valid(timer):
		timer.wait_time = get_weapon_cooldown_value(weapon_entry)
		timer.start()

func get_weapon_cooldown_value(weapon_entry: Dictionary) -> float:
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	var final_cooldown = blueprint_data.cooldown
	var p_stats = (get_parent() as PlayerCharacter).player_stats
	if is_instance_valid(p_stats):
		var atk_speed_mult = p_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
		if atk_speed_mult > 0: final_cooldown /= atk_speed_mult
	return maxf(0.05, final_cooldown)

func _calculate_final_weapon_stat(weapon_entry: Dictionary, stat_key: StringName) -> float:
	var base_value = float(weapon_entry.specific_stats.get(stat_key, 0.0))
	var flat_mod = float(weapon_entry._flat_mods.get(stat_key, 0.0))
	var percent_add_mod = float(weapon_entry._percent_add_mods.get(stat_key, 0.0))
	var percent_mult_final_mod = float(weapon_entry._percent_mult_final_mods.get(stat_key, 1.0))
	return (base_value + flat_mod) * (1.0 + percent_add_mod) * percent_mult_final_mod

# This is the updated function.
func apply_weapon_upgrade(weapon_id: StringName, upgrade_data: WeaponUpgradeData):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return
	var weapon_entry = active_weapons[weapon_index]
	var owner_player = get_parent() as PlayerCharacter
	if upgrade_data.set_acquired_flag_on_weapon != &"":
		weapon_entry.specific_stats[upgrade_data.set_acquired_flag_on_weapon] = true
	for effect in upgrade_data.effects:
		if effect is StatModificationEffectData:
			var stat_mod = effect as StatModificationEffectData
			match stat_mod.target_scope:
				&"player_stats": owner_player.player_stats.apply_stat_modification(stat_mod)
				&"weapon_specific_stats":
					var key = stat_mod.stat_key
					var value = stat_mod.get_value()
					match stat_mod.modification_type:
						&"flat_add": weapon_entry._flat_mods[key] = weapon_entry._flat_mods.get(key, 0.0) + value
						&"percent_add_to_base": weapon_entry._percent_add_mods[key] = weapon_entry._percent_add_mods.get(key, 0.0) + value
						&"percent_mult_final": weapon_entry._percent_mult_final_mods[key] = weapon_entry._percent_mult_final_mods.get(key, 1.0) * (1.0 + value)
		elif effect is CustomFlagEffectData:
			var flag_mod = effect as CustomFlagEffectData
			if flag_mod.target_scope == &"weapon_specific_stats" or flag_mod.target_scope == &"weapon_behavior":
				weapon_entry.specific_stats[flag_mod.flag_key] = flag_mod.flag_value
		elif effect is StatusEffectApplicationData:
			if not weapon_entry.specific_stats.has(&"on_hit_status_applications"):
				weapon_entry.specific_stats[&"on_hit_status_applications"] = []
			weapon_entry.specific_stats[&"on_hit_status_applications"].append(effect)
	weapon_entry.weapon_level += 1
	weapon_entry.acquired_upgrade_ids.append(upgrade_data.upgrade_id)
	emit_signal("weapon_upgraded", weapon_id, weapon_entry.weapon_level)
	emit_signal("active_weapons_changed")
	
func _get_weapon_entry_index_by_id(weapon_id: StringName) -> int:
	for i in range(active_weapons.size()):
		if active_weapons[i].id == weapon_id: return i
	return -1
	
func get_active_weapons_data_for_level_up() -> Array[Dictionary]:
	var weapons_data_copy: Array[Dictionary] = []
	for weapon_entry in active_weapons:
		var display_data = {
			"id": weapon_entry.id,
			"title": weapon_entry.title,
			"weapon_level": weapon_entry.weapon_level,
			# This is the key change: we pass the entire specific_stats dictionary,
			# which includes all the boolean flags for acquired upgrades.
			"specific_stats": weapon_entry.specific_stats.duplicate(true),
			"blueprint_resource_path": weapon_entry.blueprint_resource.resource_path if is_instance_valid(weapon_entry.blueprint_resource) else ""
		}
		weapons_data_copy.append(display_data)
	return weapons_data_copy
