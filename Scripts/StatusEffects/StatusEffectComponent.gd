## File: res/Scripts/StatusEffects/StatusEffectComponent.gd
# MERGED: This version contains your script's logic combined with the new global signal emission.

class_name StatusEffectComponent
extends Node

signal status_effects_changed(owner_node: Node)

var active_effects: Dictionary = {}

var _additive_modifiers: Dictionary = {}
var _multiplicative_modifiers: Dictionary = {}
var _active_flags: Dictionary = {}

func apply_effect(
		effect_data: StatusEffectData,
		source_node: Node = null,
		p_weapon_stats_for_scaling: Dictionary = {},
		duration_override: float = -1.0,
		potency_override: float = -1.0,
		p_unique_id_override: StringName = &""
	):
	if not is_instance_valid(effect_data) or effect_data.id == &"":
		push_error("StatusEffectComponent: Invalid StatusEffectData provided."); return

	var base_id = effect_data.id
	var final_effect_key = base_id
	var is_newly_applied = false # Flag to track if this is a brand new application

	if p_unique_id_override != &"":
		final_effect_key = p_unique_id_override
	elif effect_data.is_stackable and not effect_data.refresh_duration_on_reapply:
		var stack_counter = 0
		while active_effects.has(str(base_id) + str(stack_counter)):
			stack_counter += 1
		final_effect_key = str(base_id) + str(stack_counter)

	if active_effects.has(final_effect_key):
		# Handle re-application of an existing effect.
		var existing_effect = active_effects[final_effect_key]
		if effect_data.is_stackable and existing_effect.stacks < effect_data.max_stacks:
			existing_effect.stacks += 1
		if effect_data.refresh_duration_on_reapply:
			var final_duration = duration_override if duration_override >= 0.0 else effect_data.duration
			if final_duration > 0 and is_instance_valid(existing_effect.duration_timer):
				existing_effect.duration_timer.wait_time = final_duration
				existing_effect.duration_timer.start()
	else:
		# Handle application of a new effect.
		is_newly_applied = true # This is a new effect instance
		var new_effect_entry = {
			"base_id": base_id, "unique_id": final_effect_key,
			"data": effect_data, "duration_timer": null, "tick_timer": null, "stacks": 1,
			"source": source_node, "weapon_stats": p_weapon_stats_for_scaling.duplicate(true),
			"potency_override": potency_override, "stored_tick_damage": 0.0
		}
		
		# (DoT logic remains the same)
		var is_dot_effect = false
		for effect in effect_data.effects_while_active:
			if effect is StatModificationEffectData and effect.stat_key == &"health":
				is_dot_effect = true
				break
		if is_dot_effect:
			var source_player_stats = source_node.player_stats if is_instance_valid(source_node) and "player_stats" in source_node else null
			if is_instance_valid(source_player_stats):
				var weapon_dmg_percent = float(p_weapon_stats_for_scaling.get(&"weapon_damage_percentage", 1.0))
				var weapon_tags: Array[StringName] = []
				var retrieved_tags = p_weapon_stats_for_scaling.get(&"tags", [])
				if retrieved_tags is Array: weapon_tags.assign(retrieved_tags)
				new_effect_entry.stored_tick_damage = source_player_stats.get_calculated_player_damage(weapon_dmg_percent, weapon_tags)
		
		var final_duration = duration_override if duration_override >= 0.0 else effect_data.duration
		if final_duration > 0:
			var duration_timer = Timer.new(); duration_timer.name = "DurationTimer_" + str(final_effect_key)
			duration_timer.one_shot = true; duration_timer.wait_time = final_duration
			duration_timer.timeout.connect(_on_effect_expired.bind(final_effect_key))
			add_child(duration_timer); duration_timer.start()
			new_effect_entry.duration_timer = duration_timer

		if effect_data.tick_interval > 0:
			var tick_timer = Timer.new(); tick_timer.name = "TickTimer_" + str(final_effect_key)
			tick_timer.wait_time = effect_data.tick_interval
			tick_timer.timeout.connect(_on_status_effect_tick.bind(final_effect_key))
			add_child(tick_timer); tick_timer.start()
			if effect_data.tick_on_application: _on_status_effect_tick(final_effect_key)
			new_effect_entry.tick_timer = tick_timer
			
		active_effects[final_effect_key] = new_effect_entry
		
		# --- Visual Effect Spawning Logic ---
		if is_instance_valid(effect_data.visual_effect_scene):
			var owner_node = get_parent()
			if is_instance_valid(owner_node):
				var visual_instance = effect_data.visual_effect_scene.instantiate()
				if visual_instance.has_method("initialize"):
					visual_instance.initialize(
						owner_node, 
						final_duration, 
						effect_data.visual_anchor_point, 
						effect_data.visual_scale_multiplier
					)
				else:
					owner_node.add_child(visual_instance)
	
	# --- MERGED CHANGE: Emit Global Signal ---
	# This happens on both new applications and re-applications.
	# We check if it's newly applied to trigger reactive abilities like Chain Bash.
	if is_newly_applied:
		CombatEvents.emit_signal("status_effect_applied", get_parent(), effect_data.id, source_node)

	_recalculate_and_apply_stat_modifiers()
	var owner_node_for_signal = get_parent()
	if is_instance_valid(owner_node_for_signal): 
		emit_signal("status_effects_changed", owner_node_for_signal)

func _on_status_effect_tick(effect_unique_id: StringName):
	if not active_effects.has(effect_unique_id): return
	var owner = get_parent()
	if not is_instance_valid(owner): return
	var effect_entry = active_effects[effect_unique_id]
	var status_data = effect_entry.data as StatusEffectData
	for effect in status_data.effects_while_active:
		if effect is StatModificationEffectData:
			var stat_mod = effect as StatModificationEffectData
			if stat_mod.stat_key == &"health" and stat_mod.modification_type == &"flat_add":
				var damage_per_tick = 0.0
				if status_data.id == &"poison":
					damage_per_tick = effect_entry.stored_tick_damage * 0.5
				else:
					if status_data.duration > 0 and status_data.tick_interval > 0:
						var num_ticks = status_data.duration / status_data.tick_interval
						damage_per_tick = effect_entry.stored_tick_damage / num_ticks
				var actual_potency_override = effect_entry.get("potency_override", -1.0)
				if actual_potency_override >= 0.0: damage_per_tick *= actual_potency_override
				damage_per_tick *= effect_entry.stacks
				var final_tick_damage = absf(damage_per_tick)
				final_tick_damage = maxf(1.0, final_tick_damage)
				if owner.has_method("take_damage"):
					owner.take_damage(final_tick_damage, effect_entry.source)


func _on_effect_expired(effect_unique_id: StringName):
	if active_effects.has(effect_unique_id):
		# FIX: Use get() and then erase() instead of pop_back().
		var effect_entry = active_effects.get(effect_unique_id)
		active_effects.erase(effect_unique_id)
		
		# Make sure we actually got the data before proceeding.
		if effect_entry:
			if is_instance_valid(effect_entry.duration_timer): 
				effect_entry.duration_timer.queue_free()
			if is_instance_valid(effect_entry.tick_timer): 
				effect_entry.tick_timer.queue_free()
			
			_recalculate_and_apply_stat_modifiers()
			var owner_node = get_parent()
			if is_instance_valid(owner_node): 
				emit_signal("status_effects_changed", owner_node)
			
			var status_data_to_check = effect_entry.data as StatusEffectData
			if is_instance_valid(status_data_to_check) and status_data_to_check.next_status_effect_on_expire != &"":
				var next_effect_id = status_data_to_check.next_status_effect_on_expire
				var next_effect_path = "res://DataResources/StatusEffects/" + str(next_effect_id) + "_status.tres"
				if ResourceLoader.exists(next_effect_path):
					var next_effect_data = load(next_effect_path) as StatusEffectData
					if is_instance_valid(next_effect_data):
						apply_effect(next_effect_data, effect_entry.source, effect_entry.weapon_stats)


func _recalculate_and_apply_stat_modifiers():
	_additive_modifiers.clear()
	_multiplicative_modifiers.clear()
	_active_flags.clear()
	for key_enum_value in PlayerStatKeys.Keys.values():
		_multiplicative_modifiers[PlayerStatKeys.KEY_NAMES[key_enum_value]] = 1.0
		_additive_modifiers[PlayerStatKeys.KEY_NAMES[key_enum_value]] = 0.0
	for key in active_effects:
		var effect_entry = active_effects[key]
		var status_data = effect_entry.data as StatusEffectData
		if is_instance_valid(status_data):
			for effect in status_data.effects_while_active:
				if not is_instance_valid(effect): continue
				if effect is StatModificationEffectData:
					var stat_mod = effect as StatModificationEffectData
					var mod_value = stat_mod.get_value()
					var potency_override = effect_entry.get("potency_override", -1.0)
					if potency_override >= 0.0: mod_value *= potency_override
					if status_data.is_stackable: mod_value *= effect_entry.stacks
					var stat_key = stat_mod.stat_key; var type = stat_mod.modification_type
					if not (stat_key == &"health" and type == &"flat_add"):
						match type:
							&"flat_add", &"percent_add_to_base": _additive_modifiers[stat_key] = _additive_modifiers.get(stat_key, 0.0) + mod_value
							&"percent_mult_final": _multiplicative_modifiers[stat_key] = _multiplicative_modifiers.get(stat_key, 1.0) * (1.0 + mod_value)
				elif effect is CustomFlagEffectData:
					var flag_effect = effect as CustomFlagEffectData
					if _active_flags.get(flag_effect.flag_key, false) == false:
						_active_flags[flag_effect.flag_key] = flag_effect.flag_value
	emit_signal("status_effects_changed", get_parent())

# --- Getter Functions ---

func get_sum_of_additive_modifiers(stat_key: StringName) -> float:
	return _additive_modifiers.get(stat_key, 0.0)

func get_product_of_multiplicative_modifiers(stat_key: StringName) -> float:
	return _multiplicative_modifiers.get(stat_key, 1.0)

func has_flag(flag_key: StringName) -> bool:
	return _active_flags.get(flag_key, false)

func has_status_effect(effect_id: StringName) -> bool:
	return has_status_effect_with_base_id(effect_id)

# --- NEW HELPER FUNCTIONS ---

func has_status_effect_with_base_id(p_base_id: StringName) -> bool:
	for key in active_effects:
		if active_effects[key].get("base_id") == p_base_id:
			return true
	return false

func has_status_effect_by_unique_id(p_unique_id: StringName) -> bool:
	return active_effects.has(p_unique_id)

func get_stats_from_effect_source_by_unique_id(p_unique_id: StringName) -> Dictionary:
	if active_effects.has(p_unique_id):
		return active_effects[p_unique_id].get("weapon_stats", {})
	return {}
