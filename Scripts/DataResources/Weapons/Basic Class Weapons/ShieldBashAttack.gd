# File: res://Scripts/Weapons/ShieldBashAttack.gd
# REVISED: Flipping logic has been removed. This now relies on the scene
# being set up correctly with the sprite facing right by default.

class_name ShieldBashAttack
extends Area2D

const PHANTOM_BASH_SCENE = preload("res://Scenes/Effects/PhantomBashExplosion.tscn")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionPolygon2D = $CollisionPolygon2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var specific_stats: Dictionary = {}
var owner_player_stats: PlayerStats = null
var _enemies_hit_this_sweep: Array[Node2D] = []

func _ready():
	if not is_instance_valid(animated_sprite): push_error("ERROR (ShieldBashAttack): No AnimatedSprite2D found!")
	if not is_instance_valid(collision_shape): push_error("ERROR (ShieldBashAttack): No CollisionPolygon2D found!"); queue_free(); return
	if not is_instance_valid(lifetime_timer): push_error("ERROR (ShieldBashAttack): No LifetimeTimer found!"); queue_free(); return
	
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)
	tree_exiting.connect(_on_tree_exiting)

	collision_shape.disabled = false

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	specific_stats = p_attack_stats.duplicate(true)
	owner_player_stats = p_player_stats
	
	if direction != Vector2.ZERO:
		self.rotation = direction.angle()

	var base_scale_x = float(specific_stats.get(&"inherent_visual_scale_x", 1.0))
	var base_scale_y = float(specific_stats.get(&"inherent_visual_scale_y", 1.0))
	var weapon_area_scale = float(specific_stats.get(&"area_scale", 1.0))
	var player_aoe_multiplier = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	var final_scale_x = base_scale_x * weapon_area_scale * player_aoe_multiplier
	var final_scale_y = base_scale_y * weapon_area_scale * player_aoe_multiplier
	self.scale = Vector2(final_scale_x, final_scale_y)
	
	var base_duration = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.BASE_ATTACK_DURATION], 0.2))
	var effect_duration_multiplier = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	lifetime_timer.wait_time = base_duration * effect_duration_multiplier
	lifetime_timer.start()

	if is_instance_valid(animated_sprite):
		animated_sprite.play("bash")
		
	# --- REVISED: Phantom Bash Logic ---
	if specific_stats.get(&"has_phantom_bash", false):
		var aftershock = PHANTOM_BASH_SCENE.instantiate()
		
		# FIX: Add the explosion to the main scene tree, not this short-lived node.
		# This ensures it survives after the shield bash animation is gone.
		var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
		if is_instance_valid(attacks_container):
			attacks_container.add_child(aftershock)
		else:
			get_tree().current_scene.add_child(aftershock)
		
		# Set its global position to match this attack's position.
		aftershock.global_position = self.global_position
		
		var detonate_timer = get_tree().create_timer(1.0)
		
		var weapon_damage_percent = float(specific_stats.get(&"weapon_damage_percentage", 1.2))
		var weapon_tags: Array[StringName] = specific_stats.get(&"tags", [])
		
		# --- REFACTORED DAMAGE CALCULATION ---
		var base_damage = owner_player_stats.get_calculated_base_damage(weapon_damage_percent)
		var final_damage = owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
		var explosion_damage = int(round(final_damage))
		# --- END REFACTOR ---
		
		var explosion_radius = float(specific_stats.get(&"phantom_bash_radius", 50.0))
		var owner_player = p_player_stats.get_parent()
		
		detonate_timer.timeout.connect(aftershock.detonate.bind(
			explosion_damage,
			explosion_radius,
			owner_player,
			{},
			specific_stats
		))

func _on_body_entered(body: Node2D):
	if _enemies_hit_this_sweep.has(body): return
	if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
		var enemy_target = body as BaseEnemy
		_enemies_hit_this_sweep.append(enemy_target)
		
		if not is_instance_valid(owner_player_stats):
			push_error("ERROR (ShieldBashAttack): owner_player_stats is invalid. Cannot deal damage."); return

		var weapon_damage_percent = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 1.2))
		var weapon_tags: Array[StringName] = []
		if specific_stats.has("tags"):
			weapon_tags = specific_stats.get("tags")
			
		# --- REFACTORED DAMAGE CALCULATION ---
		var base_damage = owner_player_stats.get_calculated_base_damage(weapon_damage_percent)
		var calculated_damage_float = owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
		# --- END REFACTOR ---

		var final_damage_to_deal = int(round(maxf(1.0, calculated_damage_float)))
		
		var owner_player_char = owner_player_stats.get_parent()
		
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}
		enemy_target.take_damage(final_damage_to_deal, owner_player_char, attack_stats_for_enemy, weapon_tags) # Pass tags

		
		var global_lifesteal_percent = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
		if global_lifesteal_percent > 0:
			var heal_amount = final_damage_to_deal * global_lifesteal_percent
			if is_instance_valid(owner_player_char) and owner_player_char.has_method("heal"):
				owner_player_char.heal(heal_amount)

		var knockback_strength = float(specific_stats.get(&"knockback_strength", 150.0))
		if knockback_strength > 0 and enemy_target.has_method("apply_knockback"):
			var knockback_direction = (enemy_target.global_position - owner_player_char.global_position).normalized()
			enemy_target.apply_knockback(knockback_direction, knockback_strength)

		if specific_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy_target.status_effect_component):
			var status_apps: Array = specific_stats.get(&"on_hit_status_applications", [])
			var global_status_effect_chance_add = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)

			for app_data_res in status_apps:
				var app_data = app_data_res as StatusEffectApplicationData
				if is_instance_valid(app_data):
					var final_application_chance = app_data.application_chance + global_status_effect_chance_add
					final_application_chance = clampf(final_application_chance, 0.0, 1.0)
					
					if randf() < final_application_chance:
						enemy_target.status_effect_component.apply_effect(
							load(app_data.status_effect_resource_path) as StatusEffectData,
							owner_player_char,
							specific_stats,
							app_data.duration_override,
							app_data.potency_override
						)
		
func _on_tree_exiting():
	if _enemies_hit_this_sweep.size() > 0 and specific_stats.get(&"has_resolute_defense", false):
		var player = owner_player_stats.get_parent()
		var player_status_comp = player.get_node_or_null("StatusEffectComponent")
		
		if is_instance_valid(player_status_comp):
			var hits = _enemies_hit_this_sweep.size()
			var total_regen_percent = min(0.20, float(hits) * 0.01)
			
			print("DEBUG (Resolute Defense): Hit ", hits, " enemies. Applying buff with ", total_regen_percent * 100, "% max HP regen.")
			
			var buff_data = load("res://DataResources/StatusEffects/resolute_defense_status.tres")
			if is_instance_valid(buff_data):
				player_status_comp.apply_effect(buff_data, player, {}, 2.0, total_regen_percent)
