# File: RingOfShards.gd
# Attach to: RingOfShards.tscn (root Area2D)
# --------------------------------------------------------------------
class_name RingOfShards
extends Area2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_shape: CollisionShape2D = $DamageShape
@onready var taunt_area: Area2D = $TauntArea
@onready var damage_tick_timer: Timer = $DamageTickTimer
@onready var lifetime_timer: Timer = $LifetimeTimer

const SLOW_STATUS_DATA = preload("res://DataResources/StatusEffects/slow_status.tres")

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _tick_damage: int
var _game_node: Node # Reference to the main game node

func _ready():
	# Connections are now more carefully managed in initialize
	pass

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats

	var is_shattered_illusion_spawn = _specific_stats.get("is_shattered_illusion_spawn", false)

	# Calculate damage per tick
	var tick_damage_percent = float(_specific_stats.get("ring_tick_damage_percentage", 0.4))
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	var base_damage = _owner_player_stats.get_calculated_base_damage(tick_damage_percent)
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_tick_damage = final_damage
	# Configure timers
	damage_tick_timer.wait_time = float(_specific_stats.get("ring_tick_interval", 0.5))
	
	# --- REVISED LIFETIME LOGIC ---
	if is_shattered_illusion_spawn:
		# Spawned rings have a simple, fixed lifetime and just disappear.
		lifetime_timer.wait_time = 1.1 # 1s lifetime + 0.1s buffer
		if not lifetime_timer.is_connected("timeout", queue_free):
			lifetime_timer.timeout.connect(queue_free)
	else:
		# Original rings have complex expiration logic.
		lifetime_timer.wait_time = float(_specific_stats.get("ring_duration", 2.5))
		if not lifetime_timer.is_connected("timeout", _on_lifetime_expired):
			lifetime_timer.timeout.connect(_on_lifetime_expired)

	damage_tick_timer.timeout.connect(_on_damage_tick)
	body_entered.connect(_on_body_entered)
	
	damage_tick_timer.start()
	lifetime_timer.start()

	# Configure radii and scales
	var base_radius = float(_specific_stats.get("ring_radius", 80.0))
	var taunt_mult = float(_specific_stats.get("taunt_radius_multiplier", 1.5))
	var player_aoe_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	
	var final_radius = base_radius * player_aoe_mult
	
	if damage_shape.shape is CircleShape2D:
		(damage_shape.shape as CircleShape2D).radius = final_radius
	
	var taunt_shape = taunt_area.get_node("TauntShape") as CollisionShape2D
	if taunt_shape.shape is CircleShape2D:
		(taunt_shape.shape as CircleShape2D).radius = final_radius * taunt_mult

	# Scale sprite visual to match damage radius
	var sprite_texture = sprite.sprite_frames.get_frame_texture("active", 0)
	if is_instance_valid(sprite_texture):
		var texture_size = sprite_texture.get_width()
		if texture_size > 0:
			sprite.scale = Vector2.ONE * (final_radius * 2 / texture_size)
	
	sprite.play("active") # Assuming a looping "active" animation
	
	# Connect to the global enemy death signal for Shattered Illusion
	_game_node = get_tree().root.get_node_or_null("Game")
	if is_instance_valid(_game_node) and _game_node.has_signal("enemy_was_killed"):
		if not _game_node.is_connected("enemy_was_killed", _on_enemy_killed):
			_game_node.enemy_was_killed.connect(_on_enemy_killed)
	else:
		push_warning("RingOfShards: Could not find Game node or 'enemy_was_killed' signal.")

func _notification(what):
	# Disconnect the signal when the ring is destroyed to prevent memory leaks.
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_game_node) and _game_node.is_connected("enemy_was_killed", _on_enemy_killed):
			_game_node.enemy_was_killed.disconnect(_on_enemy_killed)

func _physics_process(delta: float):
	# Taunt Logic
	var taunt_strength = float(_specific_stats.get("taunt_strength", 100.0))
	for body in taunt_area.get_overlapping_bodies():
		if body is BaseEnemy and not body.is_dead():
			if body.is_elite and not _specific_stats.get("has_mesmerizing_glow", false):
				continue
			var direction_to_center = (global_position - body.global_position).normalized()
			body.apply_external_force(direction_to_center * taunt_strength * delta)

func _on_damage_tick():
	# FIX: Get weapon tags and pass them to the take_damage function.
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	for body in get_overlapping_bodies():
		if body is BaseEnemy and not body.is_dead():
			body.take_damage(_tick_damage, _owner_player_stats.get_parent(), {}, weapon_tags)

func _on_body_entered(body: Node2D):
	# Enervating Field (Slow) Logic
	if _specific_stats.get("has_enervating_field", false):
		if body is BaseEnemy and is_instance_valid(body.status_effect_component):
			var weapon_tags: Array[StringName] = []
			if _specific_stats.has("tags"):
				weapon_tags = _specific_stats.get("tags")
			body.status_effect_component.apply_effect(SLOW_STATUS_DATA, _owner_player_stats.get_parent())

func _on_lifetime_expired():
	damage_tick_timer.stop()
	
	if _specific_stats.get("has_unstable_visage", false):
		_execute_unstable_visage_explosion()
	else:
		queue_free()

func _execute_unstable_visage_explosion():
	var explosion_damage_percent = float(_specific_stats.get("unstable_visage_damage_percentage", 3.0))
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	var base_damage = _owner_player_stats.get_calculated_base_damage(explosion_damage_percent)
	var explosion_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	var owner_player = _owner_player_stats.get_parent()

	var tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	var flash_tween = create_tween()
	var chain = flash_tween.chain()
	chain.tween_property(sprite, "modulate", Color.WHITE, 0.05)
	chain.tween_property(sprite, "modulate", Color.BLACK, 0.05)
	chain.tween_property(sprite, "modulate", Color.WHITE, 0.05)
	chain.tween_property(sprite, "modulate", Color(1,1,1,0), 0.05)
	
	flash_tween.finished.connect(queue_free)

	call_deferred("_deal_explosion_damage", explosion_damage, owner_player)

func _deal_explosion_damage(damage: int, source_node: Node):
	if not is_instance_valid(self): return

	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	var bodies_to_damage = get_overlapping_bodies()
	for body in bodies_to_damage:
		if body is BaseEnemy and not body.is_dead():
			body.take_damage(damage, source_node, {}, weapon_tags)

# --- Shattered Illusion Logic ---
func _on_enemy_killed(_attacker_node: Node, killed_enemy_node: Node):
	if not _specific_stats.get("has_shattered_illusion", false) or not is_instance_valid(self):
		return

	var is_inside = false
	for body in get_overlapping_bodies():
		if body == killed_enemy_node:
			is_inside = true
			break
	
	if is_inside:
		if randf() < 0.25:
			# FIX: Defer the spawning of the new ring.
			call_deferred("_spawn_shattered_illusion_ring", killed_enemy_node.global_position)

func _spawn_shattered_illusion_ring(position: Vector2):
	var ring_instance = load("res://Scenes/Weapons/Advanced/Effect Scenes/RingOfShards.tscn").instantiate()
	get_tree().current_scene.add_child(ring_instance)
	ring_instance.global_position = position
	
	var shattered_stats = _specific_stats.duplicate(true)
	shattered_stats["ring_radius"] = float(_specific_stats.get("ring_radius", 80.0)) * 0.5
	shattered_stats["ring_duration"] = 1.0 
	shattered_stats["has_shattered_illusion"] = false
	shattered_stats["has_unstable_visage"] = false
	shattered_stats["is_shattered_illusion_spawn"] = true # Add a flag to identify this as a spawned ring

	if ring_instance.has_method("initialize"):
		ring_instance.initialize(shattered_stats, _owner_player_stats)
