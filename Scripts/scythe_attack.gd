# scythe_attack.gd
# This is the definitive, redesigned version of the Scythe's attack script.
# It correctly handles all unique upgrades passed to it by the WeaponManager.
class_name ScytheAttack
extends Node2D

signal reaping_momentum_hits(hit_count: int)

# --- Components ---
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var damage_area: Area2D = get_node_or_null("DamageArea") as Area2D

# --- Attack State ---
var _specific_stats: Dictionary = {}   
var _owner_player_stats: PlayerStats = null
var _enemies_hit_this_sweep: Array[Node2D] = []
var _is_attack_active: bool = false
var _current_attack_duration: float = 0.5 

func _ready():
	if not is_instance_valid(animated_sprite) or not is_instance_valid(damage_area):
		print_debug("ERROR (ScytheAttack): Required child nodes are missing."); queue_free(); return
	
	damage_area.body_entered.connect(Callable(self, "_on_damage_area_body_entered"))
	
	var collision_shape = damage_area.get_node_or_null("CollisionShape2D")
	if is_instance_valid(collision_shape):
		collision_shape.disabled = true

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_attack_stats.duplicate(true)
	_owner_player_stats = p_player_stats
	
	if direction != Vector2.ZERO:
		self.rotation = direction.angle()

	_apply_visuals_and_timing()
	# The attack sequence is now an async function, so we call it without await here.
	# It will manage its own lifetime.
	_start_attack_sequence()

func _apply_visuals_and_timing():
	if not is_instance_valid(self) or _specific_stats.is_empty(): return

	# --- CORRECTED: Wider Arc Logic ---
	var base_scale_x = float(_specific_stats.get("inherent_visual_scale_x", 1.0))
	var base_scale_y = float(_specific_stats.get("inherent_visual_scale_y", 1.0))
	# Get the weapon-specific multiplier (which starts at 1.0 and is added to by the upgrade)
	var weapon_aoe_mult = float(_specific_stats.get("aoe_area_multiplier", 1.0))
	var player_aoe_mult = 1.0
	if is_instance_valid(_owner_player_stats):
		player_aoe_mult = _owner_player_stats.get_current_aoe_area_multiplier()
	# The final scale combines the base scale, the weapon's own AoE bonus, and any global player multiplier.
	self.scale = Vector2(base_scale_x * weapon_aoe_mult * player_aoe_mult, base_scale_y * weapon_aoe_mult * player_aoe_mult)
	
	# Apply attack speed from stats
	var base_duration = float(_specific_stats.get("base_attack_duration", 0.5))
	var atk_speed_player_mult = 1.0 
	if is_instance_valid(_owner_player_stats):
		atk_speed_player_mult = _owner_player_stats.get_current_attack_speed_multiplier()
	var final_attack_speed_mult = atk_speed_player_mult
	if final_attack_speed_mult <= 0: final_attack_speed_mult = 0.01
	_current_attack_duration = base_duration / final_attack_speed_mult
	if is_instance_valid(animated_sprite):
		animated_sprite.speed_scale = final_attack_speed_mult
	
func _start_attack_sequence() -> void:
	# --- CORRECTED: Whirlwind Technique Logic ---
	var number_of_spins = 1
	if _specific_stats.get("has_whirlwind", false):
		number_of_spins = int(_specific_stats.get("whirlwind_count", 1))
	
	var spin_delay = float(_specific_stats.get("whirlwind_delay", 0.1))
	
	# This logic now correctly handles multiple, distinct slashes.
	for i in range(number_of_spins):
		if i > 0:
			await get_tree().create_timer(spin_delay).timeout
		# Check if the node was freed during the await (e.g., player died)
		if not is_instance_valid(self): return
		_perform_single_slash()
		# Wait for the slash animation to finish before starting the next one
		await get_tree().create_timer(_current_attack_duration).timeout
	
	# After all slashes and delays are finished, free the node.
	if is_instance_valid(self):
		call_deferred("queue_free")

func _perform_single_slash():
	_enemies_hit_this_sweep.clear()
	_is_attack_active = true
	
	var collision_shape = damage_area.get_node_or_null("CollisionShape2D")
	if is_instance_valid(collision_shape): collision_shape.disabled = false

	animated_sprite.play("slash")
	
	# Use a one-shot timer to disable the hitbox after this single slash is done
	var timer = get_tree().create_timer(_current_attack_duration, true, false, true)
	timer.timeout.connect(func(): 
		if is_instance_valid(self): 
			_is_attack_active = false
			if is_instance_valid(collision_shape):
				collision_shape.disabled = true
	)

func _on_damage_area_body_entered(body: Node2D):
	if not _is_attack_active or not is_instance_valid(body) or _enemies_hit_this_sweep.has(body): return
	
	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return
		_enemies_hit_this_sweep.append(enemy_target)
		
		var owner_player = _owner_player_stats.get_parent() if is_instance_valid(_owner_player_stats) else null
		if not is_instance_valid(owner_player): return

		# --- Damage Calculation ---
		var player_base_damage = float(_owner_player_stats.get_current_base_numerical_damage())
		var player_global_mult = float(_owner_player_stats.get_current_global_damage_multiplier())
		var weapon_damage_percent = float(_specific_stats.get("weapon_damage_percentage", 1.5))
		var calculated_damage = player_base_damage * weapon_damage_percent
		
		var reaping_bonus = int(_specific_stats.get("reaping_momentum_bonus_to_apply", 0))
		calculated_damage += reaping_bonus
		
		var final_damage = calculated_damage * player_global_mult
		var final_damage_to_deal = int(round(max(1.0, final_damage)))
		
		enemy_target.take_damage(final_damage_to_deal, owner_player)
		
		# --- On-Hit Effects ---
		if _specific_stats.get("has_reaping_momentum", false):
			emit_signal("reaping_momentum_hits", 1)
		
		var on_hit_applications = _specific_stats.get("on_hit_status_applications", []) as Array
		if not on_hit_applications.is_empty():
			var enemy_status_comp = enemy_target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
			if is_instance_valid(enemy_status_comp):
				for app_data_res in on_hit_applications:
					if is_instance_valid(app_data_res) and app_data_res is StatusEffectApplicationData:
						var app_data = app_data_res as StatusEffectApplicationData
						if randf() < app_data.application_chance:
							var status_effect_def = load(app_data.status_effect_resource_path) as StatusEffectData
							if is_instance_valid(status_effect_def):
								enemy_status_comp.apply_effect(status_effect_def, owner_player, _specific_stats, app_data.duration_override, app_data.potency_override)

		# --- On-Kill Effects ---
		if _specific_stats.get("has_soul_siphon", false) and enemy_target.is_dead(): 
			var siphon_details = _specific_stats.get("soul_siphon_details", {}) 
			var chance = float(siphon_details.get("chance", 0.1))
			if randf() < chance:
				if owner_player.has_method("heal"):
					var base_heal = int(siphon_details.get("base_heal", 3))
					var player_luck = _owner_player_stats.get_luck()
					var effective_luck = max(1, player_luck)
					owner_player.heal(base_heal * effective_luck)
