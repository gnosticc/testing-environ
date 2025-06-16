# WeaponManager.gd
# This is the complete, merged, and definitive version of the WeaponManager.
# CORRECTED: The attack logic now correctly handles Blade Flurry procs for both
# the primary and Holy Infusion swings, and spawns the flurry at the correct location.

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
	
	var riposte_multiplier = 1.0
	if weapon_entry.specific_stats.get(&"has_parry_riposte", false):
		if weapon_entry.specific_stats.get("parry_riposte_bonus_active", false):
			riposte_multiplier = 3.0
		weapon_entry.specific_stats["parry_riposte_bonus_active"] = true

	var reaping_bonus = int(weapon_entry.specific_stats.get(&"reaping_momentum_accumulated_bonus", 0))

	# --- Primary Attack & Flurry Check ---
	var primary_attack = _spawn_attack_instance(weapon_entry, reaping_bonus, true, riposte_multiplier)
	if is_instance_valid(primary_attack) and weapon_entry.specific_stats.get(&"has_blade_flurry", false):
		if randf() < float(weapon_entry.specific_stats.get(&"blade_flurry_chance", 0.0)):
			get_tree().create_timer(0.2, false).timeout.connect(_on_blade_flurry_timeout.bind(weapon_entry, riposte_multiplier, primary_attack.global_transform))

	# --- Holy Infusion & Flurry Check ---
	if weapon_entry.specific_stats.get(&"has_holy_infusion", false):
		var owner_player = get_parent() as PlayerCharacter
		if is_instance_valid(owner_player) and is_instance_valid(owner_player.melee_aiming_dot):
			var opposite_local_pos = owner_player.melee_aiming_dot.position * -1
			var opposite_global_pos = owner_player.to_global(opposite_local_pos)
			var opposite_rotation = (owner_player.melee_aiming_dot.global_position - owner_player.global_position).angle() + PI
			var opposite_transform = Transform2D(opposite_rotation, opposite_global_pos)
			
			var opposite_swing = _spawn_attack_instance(weapon_entry, 0, false, riposte_multiplier, opposite_transform)
			if is_instance_valid(opposite_swing) and weapon_entry.specific_stats.get(&"has_blade_flurry", false):
				if randf() < float(weapon_entry.specific_stats.get(&"blade_flurry_chance", 0.0)):
					get_tree().create_timer(0.2, false).timeout.connect(_on_blade_flurry_timeout.bind(weapon_entry, riposte_multiplier, opposite_swing.global_transform))

	# --- Scythe Whirlwind ---
	if weapon_entry.specific_stats.get(&"has_whirlwind", false):
		var number_of_spins = int(_calculate_final_weapon_stat(weapon_entry, &"whirlwind_count"))
		if number_of_spins > 1:
			var spin_delay = float(_calculate_final_weapon_stat(weapon_entry, &"whirlwind_delay"))
			var spin_data = { "weapon_id": weapon_id, "spins_left": number_of_spins - 1, "delay": spin_delay, "reaping_bonus_to_apply": reaping_bonus }
			_whirlwind_queue.append(spin_data)
			if _whirlwind_timer.is_stopped():
				_whirlwind_timer.wait_time = spin_data.delay
				_whirlwind_timer.start()

	_restart_weapon_cooldown(weapon_entry)
	
func _on_blade_flurry_timeout(weapon_entry, riposte_multiplier, spawn_transform: Transform2D):
	if is_instance_valid(self):
		_spawn_attack_instance(weapon_entry, 0, false, riposte_multiplier, spawn_transform)

func _on_whirlwind_spin_timer_timeout():
	if _whirlwind_queue.is_empty(): return
	var current_whirlwind = _whirlwind_queue.front()
	var weapon_index = _get_weapon_entry_index_by_id(current_whirlwind.weapon_id)
	if weapon_index != -1:
		_spawn_attack_instance(active_weapons[weapon_index], current_whirlwind.reaping_bonus_to_apply, false)
	current_whirlwind.spins_left -= 1
	if current_whirlwind.spins_left <= 0: _whirlwind_queue.pop_front()
	if not _whirlwind_queue.is_empty():
		var next_whirlwind = _whirlwind_queue.front()
		_whirlwind_timer.wait_time = next_whirlwind.delay
		_whirlwind_timer.start()

func _spawn_attack_instance(weapon_entry: Dictionary, p_reaping_bonus: int = 0, is_initial_swing: bool = false, p_riposte_mult: float = 1.0, p_transform_override = null) -> Node2D:
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	var owner_player = get_parent() as PlayerCharacter
	if not is_instance_valid(blueprint_data) or not is_instance_valid(owner_player): return null

	var weapon_instance = blueprint_data.weapon_scene.instantiate()
	if not is_instance_valid(weapon_instance):
		push_error("WeaponManager: Failed to instantiate weapon scene for '", blueprint_data.id, "'."); return null
		
	var final_transform: Transform2D
	var final_direction: Vector2

	if p_transform_override != null and p_transform_override is Transform2D:
		final_transform = p_transform_override
		final_direction = Vector2.RIGHT.rotated(final_transform.get_rotation())
	else:
		var spawn_position: Vector2 = owner_player.global_position
		if blueprint_data.requires_direction:
			match blueprint_data.targeting_type:
				&"nearest_enemy":
					var nearest_enemy = owner_player._find_nearest_enemy()
					if is_instance_valid(nearest_enemy): final_direction = (nearest_enemy.global_position - owner_player.global_position).normalized()
					else: return null
				&"mouse_location":
					var world_mouse_pos = owner_player.get_global_mouse_position()
					final_direction = (world_mouse_pos - owner_player.global_position).normalized()
					var max_range = float(_calculate_final_weapon_stat(weapon_entry, PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAX_CAST_RANGE]))
					max_range += owner_player.player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_MAX_RANGE_ADD)
					spawn_position = owner_player.global_position.move_toward(world_mouse_pos, max_range)
				&"mouse_direction":
					if is_instance_valid(owner_player.melee_aiming_dot) and owner_player.melee_aiming_dot.has_method("get_aiming_direction"):
						final_direction = owner_player.melee_aiming_dot.get_aiming_direction()
					else:
						final_direction = (owner_player.get_global_mouse_position() - owner_player.global_position).normalized()
						if final_direction == Vector2.ZERO: final_direction = Vector2.RIGHT
		
		if blueprint_data.spawn_as_child:
			var local_pos = owner_player.melee_aiming_dot.position if is_instance_valid(owner_player.melee_aiming_dot) and blueprint_data.tags.has("melee") else Vector2.ZERO
			spawn_position = owner_player.to_global(local_pos)
		final_transform = Transform2D(final_direction.angle(), spawn_position)

	owner_player.add_child(weapon_instance)
	weapon_instance.global_transform = final_transform
	
	var stats_to_pass = {}
	for key in weapon_entry.specific_stats.keys():
		var value = weapon_entry.specific_stats[key]
		if value is int or value is float: stats_to_pass[key] = _calculate_final_weapon_stat(weapon_entry, key)
		else: stats_to_pass[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	
	stats_to_pass["tags"] = weapon_entry.tags.duplicate(true)
	var final_damage = owner_player.player_stats.get_calculated_player_damage(stats_to_pass[&"weapon_damage_percentage"], stats_to_pass["tags"])
	stats_to_pass["final_damage_amount"] = final_damage * p_riposte_mult
	
	if stats_to_pass.has(&"projectile_speed"):
		var base_proj_speed = stats_to_pass[&"projectile_speed"]
		var weapon_proj_speed_mult = _calculate_final_weapon_stat(weapon_entry, &"projectile_speed_multiplier")
		var player_proj_speed_mult = owner_player.player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
		stats_to_pass[&"final_projectile_speed"] = base_proj_speed * weapon_proj_speed_mult * player_proj_speed_mult
	
	stats_to_pass[&"reaping_momentum_accumulated_bonus"] = p_reaping_bonus
	if is_initial_swing:
		weapon_entry.specific_stats[&"reaping_momentum_accumulated_bonus"] = 0

	if weapon_instance.has_method("set_attack_properties"):
		weapon_instance.set_attack_properties(final_direction, stats_to_pass, owner_player.player_stats)
	
	if weapon_instance.has_signal("attack_hit_enemy"):
		weapon_instance.attack_hit_enemy.connect(_on_attack_hit_enemy.bind(weapon_entry.id), CONNECT_ONE_SHOT)
	if weapon_instance.has_signal("reaping_momentum_hit"):
		weapon_instance.reaping_momentum_hit.connect(_on_reaping_momentum_hit.bind(weapon_entry.id))

	return weapon_instance

func _on_attack_hit_enemy(hit_count: int, weapon_id: StringName):
	if hit_count > 0:
		var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
		if weapon_index != -1:
			active_weapons[weapon_index].specific_stats["parry_riposte_bonus_active"] = false
			
func _on_reaping_momentum_hit(hit_count: int, weapon_id: StringName):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return
	var weapon_entry = active_weapons[weapon_index]
	var dmg_per_hit = int(_calculate_final_weapon_stat(weapon_entry, &"reaping_momentum_damage_per_hit"))
	var current_bonus = weapon_entry.specific_stats.get(&"reaping_momentum_accumulated_bonus", 0)
	weapon_entry.specific_stats[&"reaping_momentum_accumulated_bonus"] = current_bonus + (hit_count * dmg_per_hit)

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
			calculated_summon_stats[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	
	calculated_summon_stats[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE]] *= p_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_DAMAGE_MULTIPLIER)
	calculated_summon_stats[&"base_lifetime"] = blueprint_data.base_lifetime * p_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_LIFETIME_MULTIPLIER)
	calculated_summon_stats[&"weapon_id"] = weapon_entry.id
	calculated_summon_stats[&"tags"] = weapon_entry.tags.duplicate(true)

	if summon_instance.has_signal("instances_spawned"):
		if not summon_instance.is_connected("instances_spawned", _on_lesser_spirit_controller_instances_spawned):
			summon_instance.instances_spawned.connect(_on_lesser_spirit_controller_instances_spawned, CONNECT_ONE_SHOT)
	elif summon_instance.has_method("set_attack_properties"):
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

# --- [The rest of the file is unchanged] ---
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
		var global_atk_speed_mult = p_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
		var weapon_atk_speed_mult = _calculate_final_weapon_stat(weapon_entry, &"attack_speed_multiplier")
		var final_atk_speed_mult = global_atk_speed_mult * weapon_atk_speed_mult
		if final_atk_speed_mult > 0: final_cooldown /= final_atk_speed_mult
	return maxf(0.05, final_cooldown)

func _calculate_final_weapon_stat(weapon_entry: Dictionary, stat_key: StringName) -> float:
	var base_value = float(weapon_entry.specific_stats.get(stat_key, 0.0))
	var flat_mod = float(weapon_entry._flat_mods.get(stat_key, 0.0))
	var percent_add_mod = float(weapon_entry._percent_add_mods.get(stat_key, 0.0))
	var percent_mult_final_mod = float(weapon_entry._percent_mult_final_mods.get(stat_key, 1.0))
	return (base_value + flat_mod) * (1.0 + percent_add_mod) * percent_mult_final_mod
	
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
				&"player_stats":
					owner_player.player_stats.apply_stat_modification(stat_mod)
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
			"specific_stats": weapon_entry.specific_stats.duplicate(true),
			"blueprint_resource_path": weapon_entry.blueprint_resource.resource_path if is_instance_valid(weapon_entry.blueprint_resource) else ""
		}
		weapons_data_copy.append(display_data)
	return weapons_data_copy
