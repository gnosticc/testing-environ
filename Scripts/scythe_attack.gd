# scythe_attack.gd
# Refactored to be a temporary instance spawned by WeaponManager.
# Includes is_dead() debugging for Soul Siphon.
# NOW: Data-driven for on-hit status effects via StatusEffectApplicationData resources.
class_name ScytheAttack
extends Node2D 

signal attack_finished_signal
signal reaping_momentum_hits(hit_count: int) 
signal attack_finished_with_hits(hit_count: int) # For Reaping Momentum

var final_inflicted_damage: int = 10
var final_aoe_scale: Vector2 = Vector2(1.0, 1.0)

# Node references - ensure these EXACTLY match names in ScytheAttack.tscn
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var damage_area: Area2D = get_node_or_null("DamageArea") as Area2D
@onready var duration_timer: Timer = get_node_or_null("DurationTimer") as Timer

const SLASH_ANIMATION_NAME = "slash" 

var specific_stats: Dictionary = {}   
var owner_player: PlayerCharacter = null 
var weapon_manager_ref: WeaponManager = null 

var _enemies_hit_this_sweep: Array[Node2D] = []
var _is_attack_active: bool = false 
var _current_attack_duration: float = 0.5 

# is_whirlwind_instance flag remains to differentiate main swing from follow-up swings
var is_whirlwind_instance: bool = false 

func _ready():
	print_debug(name, ": _ready() called. Is Whirlwind: ", is_whirlwind_instance)

	if not is_instance_valid(animated_sprite):
		print("ERROR (ScytheAttack '", name, "'): AnimatedSprite2D node missing. Will queue_free.")
		call_deferred("queue_free")
		return
	else:
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(SLASH_ANIMATION_NAME):
			if not animated_sprite.sprite_frames.get_animation_loop(SLASH_ANIMATION_NAME):
				if not animated_sprite.is_connected("animation_finished", Callable(self, "_on_animation_finished")):
					animated_sprite.animation_finished.connect(Callable(self, "_on_animation_finished"))
		else:
			print_debug("WARNING (ScytheAttack '%s'): Animation '%s' not found." % [name, SLASH_ANIMATION_NAME])

	if not is_instance_valid(damage_area):
		print_debug("WARNING (ScytheAttack '%s'): DamageArea node missing." % name)
	else:
		if not damage_area.is_connected("body_entered", Callable(self, "_on_damage_area_body_entered")):
			damage_area.body_entered.connect(Callable(self, "_on_damage_area_body_entered"))
		var collision_shape = damage_area.get_node_or_null("CollisionShape2D")
		if is_instance_valid(collision_shape):
			collision_shape.disabled = true 
		else:
			print_debug("WARNING (ScytheAttack '%s'): No CollisionShape2D found under DamageArea." % name)


func initialize_weapon_stats_and_attack(stats_dict: Dictionary):
	specific_stats = stats_dict.duplicate(true) 
	on_stats_or_upgrades_changed()

func on_stats_or_upgrades_changed(): # Called by initialize_weapon_stats_and_attack
	if not is_instance_valid(self) or specific_stats.is_empty(): return

	# Apply Scale
	var base_scale_x = float(specific_stats.get("inherent_visual_scale_x", 1.0))
	var base_scale_y = float(specific_stats.get("inherent_visual_scale_y", 1.0))
	var player_aoe_mult = 1.0
	if is_instance_valid(owner_player) and is_instance_valid(owner_player.player_stats):
		player_aoe_mult = owner_player.player_stats.get_current_aoe_area_multiplier()
	self.scale = Vector2(base_scale_x * player_aoe_mult, base_scale_y * player_aoe_mult)
	
	# Set Attack Duration & Animation Speed
	var base_duration = float(specific_stats.get("base_attack_duration", 0.5))
	var atk_speed_player_mult = 1.0 
	if is_instance_valid(owner_player) and is_instance_valid(owner_player.player_stats):
		atk_speed_player_mult = owner_player.player_stats.get_current_attack_speed_multiplier()
	var final_attack_speed_mult = atk_speed_player_mult * float(specific_stats.get("weapon_attack_speed_mod", 1.0))
	if final_attack_speed_mult <= 0: final_attack_speed_mult = 0.01
	_current_attack_duration = base_duration / final_attack_speed_mult
	if is_instance_valid(animated_sprite):
		animated_sprite.speed_scale = final_attack_speed_mult 
	
	# Start attack sequence
	_start_attack_animation()

func _start_attack_animation():
	if not is_instance_valid(animated_sprite) or not is_instance_valid(damage_area):
		_finish_attack_sequence(true); return

	_enemies_hit_this_sweep.clear()
	_is_attack_active = true
	var collision_shape = damage_area.get_node_or_null("CollisionShape2D")
	if is_instance_valid(collision_shape): collision_shape.disabled = false

	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(SLASH_ANIMATION_NAME):
		animated_sprite.play(SLASH_ANIMATION_NAME)
		if animated_sprite.sprite_frames.get_animation_loop(SLASH_ANIMATION_NAME) or \
		   not animated_sprite.is_connected("animation_finished", Callable(self, "_on_animation_finished")):
			var duration_finish_timer = get_tree().create_timer(_current_attack_duration, true, false, true)
			duration_finish_timer.timeout.connect(Callable(self, "_finish_attack_sequence").bind(true))
	else:
		_finish_attack_sequence(true) 

func set_owner_player(p_player: PlayerCharacter):
	owner_player = p_player

func set_weapon_manager_reference(wm_node: WeaponManager):
	weapon_manager_ref = wm_node

func _on_animation_finished():
	if is_instance_valid(animated_sprite) and animated_sprite.animation == SLASH_ANIMATION_NAME:
		if not animated_sprite.sprite_frames.get_animation_loop(SLASH_ANIMATION_NAME):
			_finish_attack_sequence(false)

func _finish_attack_sequence(was_timer_based: bool):
	if _is_attack_active: 
		_is_attack_active = false
		if is_instance_valid(damage_area):
			var collision_shape = damage_area.get_node_or_null("CollisionShape2D")
			if is_instance_valid(collision_shape): collision_shape.disabled = true
		
		if specific_stats.get("has_reaping_momentum", false):
			emit_signal("reaping_momentum_hits", _enemies_hit_this_sweep.size())
		
		if was_timer_based:
			call_deferred("queue_free")

func _on_damage_area_body_entered(body: Node2D):
	if not _is_attack_active or not is_instance_valid(body) or not is_instance_valid(owner_player): return
	if _enemies_hit_this_sweep.has(body): return 
	
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		var enemy_target = body as BaseEnemy
		if not is_instance_valid(enemy_target) or enemy_target.is_dead(): return
		_enemies_hit_this_sweep.append(enemy_target)
		
		var p_stats = owner_player.player_stats as PlayerStats
		if not is_instance_valid(p_stats): return

		# --- Damage Calculation ---
		var player_base_damage = float(p_stats.get_current_base_numerical_damage())
		var player_global_mult = float(p_stats.get_current_global_damage_multiplier())
		var player_global_flat = float(p_stats.get_current_global_flat_damage_add())
		
		var weapon_scale_from_player = float(specific_stats.get("player_damage_scale_percent", 1.0))
		var weapon_percent_mod = float(specific_stats.get("weapon_damage_percentage", 1.5))
		
		var calculated_damage = player_base_damage * weapon_scale_from_player
		calculated_damage *= weapon_percent_mod
		
		var reaping_bonus = int(specific_stats.get("reaping_momentum_bonus_to_apply", 0)) 
		calculated_damage += reaping_bonus
		# Resetting the 'to_apply' bonus is handled implicitly because each instance is new.
		# The 'stored_bonus' is what's reset in the WeaponManager. reaping_bonus
		
		# NEW DEBUG PRINT: Show reaping momentum bonus
		if specific_stats.get("has_reaping_momentum", false):
			print_debug(name, ": Reaping Momentum bonus applied to this hit: ", reaping_bonus)

		# Only reset reaping momentum bonus if this is the MAIN swing instance.
		if specific_stats.get("has_reaping_momentum", false) and reaping_bonus > 0 and not is_whirlwind_instance:
			if weapon_manager_ref and weapon_manager_ref.has_method("reset_reaping_momentum_bonus_for_weapon"):
				weapon_manager_ref.reset_reaping_momentum_bonus_for_weapon(specific_stats.get("id", &""))
				print_debug(name, ": Reaping momentum bonus CONSUMED/RESET by main swing for weapon '", specific_stats.get("id", &""), "'.")
		elif is_whirlwind_instance and specific_stats.get("has_reaping_momentum", false) and reaping_bonus > 0:
			print_debug(name, ": Whirlwind swing dealt damage with bonus, but NOT resetting (only main swing resets).")


		var final_damage = (calculated_damage * player_global_mult) + player_global_flat
		var final_damage_to_deal = int(round(max(1.0, final_damage)))
		
		var attack_properties_for_enemy = { "armor_pierce": p_stats.get_current_armor_penetration() }
		
		# --- DEBUGGING for SOUL SIPHON ---
		print_debug("ScytheAttack: Enemy '", enemy_target.name, "' health BEFORE take_damage: ", enemy_target.get_current_health())
		
		enemy_target.take_damage(final_damage_to_deal, owner_player, attack_properties_for_enemy)
		
		print_debug("ScytheAttack: Enemy '", enemy_target.name, "' health AFTER take_damage: ", enemy_target.get_current_health())
		print_debug("ScytheAttack: Checking is_dead() on '", enemy_target.name, "'. Result: ", enemy_target.is_dead())

		# --- Handle On-Hit Status Effects (Data-driven) ---
		# Get the array of StatusEffectApplicationData from specific_stats
		var on_hit_applications = specific_stats.get("on_hit_status_applications", []) as Array
		if not on_hit_applications.is_empty():
			var enemy_status_comp = enemy_target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
			if is_instance_valid(enemy_status_comp):
				for app_data_res in on_hit_applications:
					if not is_instance_valid(app_data_res) or not app_data_res is StatusEffectApplicationData:
						print_debug("ScytheAttack: Skipping invalid StatusEffectApplicationData resource in on_hit_applications array.")
						continue
					
					var app_data = app_data_res as StatusEffectApplicationData
					
					# Roll for application chance
					if randf() < app_data.application_chance:
						# Use the effect_data.id property directly from the StatusEffectData resource
						# rather than trying to load it with a path. This is more robust.
						var status_effect_def = load(app_data.status_effect_resource_path) as StatusEffectData # Still need to load the resource
						if is_instance_valid(status_effect_def):
							print_debug(name, ": Applying status '", status_effect_def.id, "' (Chance: ", app_data.application_chance, ") to ", enemy_target.name)
							enemy_status_comp.apply_effect(
								status_effect_def, 
								owner_player, # Source node
								specific_stats, # Weapon stats for scaling (if needed by effect logic)
								app_data.duration_override, 
								app_data.potency_override
							)
						else:
							print_debug("ERROR (ScytheAttack): Failed to load StatusEffectData from path: ", app_data.status_effect_resource_path)
					else:
						print_debug(name, ": Status effect application chance failed for '", app_data.status_effect_resource_path, "' (Rolled: ", randf(), ", Needed: < ", app_data.application_chance, ")")

		# --- Handle Soul Siphon on kill ---
		if specific_stats.get("has_soul_siphon", false):
			if enemy_target.is_dead(): 
				print_debug("Soul Siphon Check: SUCCESS, enemy_target.is_dead() is true.")
				var siphon_details = specific_stats.get("soul_siphon_details", {}) 
				var chance = float(siphon_details.get("chance", 0.1))
				var roll = randf()
				if roll < chance:
					if owner_player.has_method("heal"):
						var base_heal = int(siphon_details.get("base_heal", 3))
						# Get player's current Luck stat from PlayerStats component
						var player_luck = 0
						if is_instance_valid(owner_player) and is_instance_valid(owner_player.player_stats):
							player_luck = owner_player.player_stats.get_luck()
						
						# Ensure a minimum luck of 1 for scaling, so it doesn't heal 0 or less
						var effective_luck = max(1, player_luck)
						
						var final_heal_amount = base_heal * effective_luck
						
						print_debug("  -> Soul Siphon SUCCESS! (Roll:", roll, "<", chance, "). Healing player for ", final_heal_amount, " (Base: ", base_heal, ", Luck: ", player_luck, ")")
						owner_player.heal(final_heal_amount)
				else:
					print_debug("  -> Soul Siphon FAILED chance roll. (Roll:", roll, ">= ", chance, ")")
			else:
				print_debug("Soul Siphon Check: FAILED, enemy_target.is_dead() is false.")
