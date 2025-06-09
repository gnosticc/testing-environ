# StatusEffectComponent.gd
# ADDED: Logic in _on_effect_expired to handle the `next_status_effect_on_expire` feature.
# UPDATED: The path logic to match the user's file structure.
class_name StatusEffectComponent
extends Node

signal status_effects_changed(owner_node: Node) 

var active_effects: Dictionary = {} 
var current_stat_modifiers: Dictionary = {}


func _ready():
	if not get_parent() is Node2D and not get_parent() is Node3D:
		print_debug("StatusEffectComponent WARNING: Owner (", get_parent().name if get_parent() else "None", ") is not Node2D/3D.")

func apply_effect(
		effect_data: StatusEffectData, 
		source_node: Node = null, 
		p_weapon_stats_for_scaling: Dictionary = {}, 
		duration_override: float = -1.0, 
		potency_override: float = -1.0 
	):
	var effect_id: StringName = effect_data.id

	if not is_instance_valid(effect_data):
		print_debug("ERROR (StatusEffectComponent): apply_effect called with invalid effect_data.")
		return
	if effect_id == &"":
		print_debug("ERROR (StatusEffectComponent): StatusEffectData has an empty ID.")
		return

	var final_duration = duration_override if duration_override >= 0.0 else effect_data.duration
	
	if active_effects.has(effect_id):
		var existing_effect_entry = active_effects[effect_id]
		
		if effect_data.refresh_duration_on_reapply:
			existing_effect_entry.source = source_node
			existing_effect_entry.weapon_stats = p_weapon_stats_for_scaling.duplicate(true)
			existing_effect_entry.potency_override = potency_override
			
			if final_duration > 0:
				if is_instance_valid(existing_effect_entry.duration_timer):
					existing_effect_entry.duration_timer.wait_time = final_duration
					existing_effect_entry.duration_timer.start()
				else: 
					var duration_timer_node = Timer.new()
					duration_timer_node.name = "DurationTimer_" + str(effect_id)
					duration_timer_node.wait_time = final_duration
					duration_timer_node.one_shot = true
					add_child(duration_timer_node)
					duration_timer_node.timeout.connect(Callable(self, "_on_effect_expired").bind(effect_id, duration_timer_node))
					duration_timer_node.start()
					existing_effect_entry.duration_timer = duration_timer_node
			else: 
				if is_instance_valid(existing_effect_entry.duration_timer):
					existing_effect_entry.duration_timer.stop()
					existing_effect_entry.duration_timer.queue_free()
					existing_effect_entry.duration_timer = null

			if effect_data.tick_interval > 0:
				if is_instance_valid(existing_effect_entry.tick_timer):
					existing_effect_entry.tick_timer.wait_time = effect_data.tick_interval
					existing_effect_entry.tick_timer.start()
				else: 
					var tick_timer_node = Timer.new()
					tick_timer_node.name = "TickTimer_" + str(effect_id)
					tick_timer_node.wait_time = effect_data.tick_interval
					tick_timer_node.one_shot = false
					add_child(tick_timer_node)
					tick_timer_node.timeout.connect(Callable(self, "_on_status_effect_tick").bind(effect_id))
					tick_timer_node.start()
					existing_effect_entry.tick_timer = tick_timer_node
				
				if effect_data.tick_on_application:
					_on_status_effect_tick(effect_id)
			else:
				if is_instance_valid(existing_effect_entry.tick_timer):
					existing_effect_entry.tick_timer.stop()
					existing_effect_entry.tick_timer.queue_free()
					existing_effect_entry.tick_timer = null

		else: 
			return

	else: 
		var new_effect_entry: Dictionary = {
			"data": effect_data,
			"duration_timer": null, 
			"tick_timer": null,
			"stacks": 1,
			"source": source_node,
			"weapon_stats": p_weapon_stats_for_scaling.duplicate(true),
			"potency_override": potency_override 
		}
		
		if final_duration > 0: 
			var duration_timer_node = Timer.new()
			duration_timer_node.name = "DurationTimer_" + str(effect_id)
			duration_timer_node.wait_time = final_duration
			duration_timer_node.one_shot = true
			add_child(duration_timer_node)
			duration_timer_node.timeout.connect(Callable(self, "_on_effect_expired").bind(effect_id, duration_timer_node))
			duration_timer_node.start()
			new_effect_entry.duration_timer = duration_timer_node
		
		if effect_data.tick_interval > 0:
			var tick_timer_node = Timer.new()
			tick_timer_node.name = "TickTimer_" + str(effect_id)
			tick_timer_node.wait_time = effect_data.tick_interval
			tick_timer_node.one_shot = false
			add_child(tick_timer_node)
			tick_timer_node.timeout.connect(Callable(self, "_on_status_effect_tick").bind(effect_id))
			tick_timer_node.start()
			new_effect_entry.tick_timer = tick_timer_node
			if effect_data.tick_on_application:
				_on_status_effect_tick(effect_id)

		active_effects[effect_id] = new_effect_entry
	
	_recalculate_and_apply_stat_modifiers()
	emit_signal("status_effects_changed", get_parent())


func _on_status_effect_tick(effect_id: StringName):
	if not active_effects.has(effect_id): return
	
	var owner = get_parent()
	if not is_instance_valid(owner) or not owner.has_method("take_damage"): return

	var effect_entry = active_effects[effect_id]
	var status_data = effect_entry.data as StatusEffectData
	
	for effect in status_data.effects_while_active:
		if effect is StatModificationEffectData:
			var stat_mod = effect as StatModificationEffectData
			
			if stat_mod.stat_key == &"health" and stat_mod.modification_type == &"flat_add":
				var damage_per_tick = stat_mod.get_value()
				var actual_potency = effect_entry.get("potency_override", 1.0)
				if actual_potency >= 0.0: damage_per_tick *= actual_potency
				var final_tick_damage = abs(damage_per_tick) 
				final_tick_damage = max(1, int(ceil(final_tick_damage))) 
				owner.take_damage(final_tick_damage, effect_entry.source)

func _on_effect_expired(effect_id_expired: StringName, duration_timer_ref: Timer): 
	if active_effects.has(effect_id_expired):
		var effect_entry = active_effects[effect_id_expired]
		var status_data_to_check = effect_entry.data as StatusEffectData
		
		var tick_timer = effect_entry.get("tick_timer") as Timer
		if is_instance_valid(tick_timer):
			tick_timer.stop(); tick_timer.queue_free()

		active_effects.erase(effect_id_expired)
		_recalculate_and_apply_stat_modifiers()
		emit_signal("status_effects_changed", get_parent()) 
		
		# NEW: Check if this effect should trigger another
		if is_instance_valid(status_data_to_check) and status_data_to_check.next_status_effect_on_expire != &"":
			var next_effect_id = status_data_to_check.next_status_effect_on_expire
			
			# UPDATED PATH: This now matches your file structure and naming convention.
			var next_effect_path = "res://DataResources/StatusEffects/" + str(next_effect_id) + "_status.tres"
			
			if ResourceLoader.exists(next_effect_path):
				var next_effect_data = load(next_effect_path) as StatusEffectData
				if is_instance_valid(next_effect_data):
					apply_effect(next_effect_data, effect_entry.source, effect_entry.weapon_stats)
			else:
				print_debug("WARNING (StatusEffectComponent): Could not find next status effect resource at: " + next_effect_path)
	
	if is_instance_valid(duration_timer_ref):
		duration_timer_ref.queue_free()
		
func remove_effect(effect_id_to_remove: StringName):
	if active_effects.has(effect_id_to_remove):
		var effect_entry = active_effects[effect_id_to_remove]
		var duration_timer = effect_entry.get("duration_timer") as Timer
		if is_instance_valid(duration_timer):
			duration_timer.stop(); duration_timer.queue_free()
		var tick_timer = effect_entry.get("tick_timer") as Timer
		if is_instance_valid(tick_timer):
			tick_timer.stop(); tick_timer.queue_free()
			
		active_effects.erase(effect_id_to_remove)
		_recalculate_and_apply_stat_modifiers()
		emit_signal("status_effects_changed", get_parent())


func _recalculate_and_apply_stat_modifiers():
	current_stat_modifiers.clear() 
	var owner = get_parent()
	if not is_instance_valid(owner): return

	for effect_id in active_effects:
		var effect_entry = active_effects[effect_id]
		var status_effect_data_res: StatusEffectData = effect_entry.data
		
		if is_instance_valid(status_effect_data_res) and not status_effect_data_res.effects_while_active.is_empty():
			for actual_effect_data_res in status_effect_data_res.effects_while_active:
				if actual_effect_data_res is StatModificationEffectData:
					var stat_mod_effect = actual_effect_data_res as StatModificationEffectData
					var mod_value = stat_mod_effect.get_value() 
					var actual_potency_override = effect_entry.get("potency_override", -1.0) 
					if actual_potency_override >= 0.0: 
						mod_value *= actual_potency_override 
					mod_value *= effect_entry.stacks
					var key_to_mod = stat_mod_effect.stat_key
					var mod_type = stat_mod_effect.modification_type

					if not (key_to_mod == &"health" and mod_type == &"flat_add"):
						if mod_type == &"percent_add_to_base": 
							current_stat_modifiers[key_to_mod] = current_stat_modifiers.get(key_to_mod, 0.0) + mod_value
						elif mod_type == &"percent_mult_final": 
							current_stat_modifiers[key_to_mod] = current_stat_modifiers.get(key_to_mod, 1.0) * (1.0 + mod_value) 
						elif mod_type == &"flat_add":
							current_stat_modifiers[key_to_mod] = current_stat_modifiers.get(key_to_mod, 0.0) + mod_value
						elif mod_type == &"override_value":
							current_stat_modifiers[key_to_mod] = mod_value
				
				elif actual_effect_data_res is CustomFlagEffectData:
					var flag_effect = actual_effect_data_res as CustomFlagEffectData
					if owner.has_method("set_behavior_flag"):
						owner.set_behavior_flag(flag_effect.flag_key, flag_effect.flag_value)
					else:
						owner.set(str(flag_effect.flag_key), flag_effect.flag_value) 
				
				elif actual_effect_data_res is TriggerAbilityEffectData:
					pass 
	
	emit_signal("status_effects_changed", owner) 


func get_sum_of_additive_modifiers(stat_key: StringName) -> float:
	return current_stat_modifiers.get(stat_key, 0.0) if current_stat_modifiers.get(stat_key) is float else 0.0
func get_product_of_multiplicative_modifiers(stat_key: StringName) -> float:
	return current_stat_modifiers.get(stat_key, 1.0) if current_stat_modifiers.get(stat_key) is float else 1.0
func get_flat_sum_modifier(stat_key: StringName) -> float: 
	return current_stat_modifiers.get(stat_key, 0.0) if current_stat_modifiers.get(stat_key) is float else 0.0
func has_status_effect(effect_id: StringName) -> bool:
	return active_effects.has(effect_id)
func get_effect_stacks(effect_id: StringName) -> int:
	if active_effects.has(effect_id): return active_effects[effect_id].stacks
	return 0
func get_effect_data_resource(effect_id: StringName) -> StatusEffectData:
	if active_effects.has(effect_id): return active_effects[effect_id].data
	return null
func has_flag(flag_key_to_check: StringName) -> bool:
	for effect_id in active_effects:
		var effect_entry = active_effects[effect_id]
		var status_effect_data_res: StatusEffectData = effect_entry.data
		if is_instance_valid(status_effect_data_res):
			for actual_effect in status_effect_data_res.effects_while_active:
				if actual_effect is CustomFlagEffectData:
					var flag_effect = actual_effect as CustomFlagEffectData
					if flag_effect.flag_key == flag_key_to_check and flag_effect.flag_value == true:
						return true
	return false
