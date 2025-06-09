# ShieldBashAttack.gd
# Behavior for the Shield Bash attack. Deals damage and applies knockback.
# CORRECTED: The rotation logic now correctly handles left-facing sprites
# by first flipping them horizontally, then applying the vertical flip for orientation.
class_name ShieldBashAttack
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var collision_shape: CollisionPolygon2D = get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer") as Timer

var specific_stats: Dictionary = {}
var owner_player_stats: PlayerStats = null
var _enemies_hit_this_sweep: Array[Node2D] = []

func _ready():
	if not is_instance_valid(animated_sprite): print("ERROR (ShieldBash): No AnimatedSprite2D found!")
	if not is_instance_valid(collision_shape): print("ERROR (ShieldBash): No CollisionPolygon2D found!"); queue_free(); return
	if not is_instance_valid(lifetime_timer): print("ERROR (ShieldBash): No LifetimeTimer found!"); queue_free(); return
	
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	specific_stats = p_attack_stats.duplicate(true)
	owner_player_stats = p_player_stats
	
	if is_instance_valid(animated_sprite):
		# Since the art asset faces left by default, we flip it horizontally
		# so that it points right, which is Godot's default 0-degree direction.
		animated_sprite.flip_h = true

	if direction != Vector2.ZERO:
		self.rotation = direction.angle()
		# Now that it's a "right-facing" sprite, we apply the standard vertical
		# flip when aiming left to prevent it from being upside down.
		if abs(direction.angle()) > PI / 2.0:
			if is_instance_valid(animated_sprite):
				animated_sprite.flip_v = true

	var base_duration = float(specific_stats.get("base_attack_duration", 0.2))
	var duration_mult = 1.0
	if is_instance_valid(owner_player_stats):
		duration_mult = owner_player_stats.get_current_effect_duration_multiplier()
	
	lifetime_timer.wait_time = base_duration * duration_mult
	lifetime_timer.start()

func _on_body_entered(body: Node2D):
	if _enemies_hit_this_sweep.has(body): return

	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return
		
		_enemies_hit_this_sweep.append(enemy_target)
		
		var player_base_damage = float(owner_player_stats.get_current_base_numerical_damage())
		var player_global_mult = float(owner_player_stats.get_current_global_damage_multiplier())
		var weapon_damage_percent = float(specific_stats.get("weapon_damage_percentage", 1.2)) # 120%
		
		var final_damage = int(round((player_base_damage * weapon_damage_percent) * player_global_mult))
		var owner_player = owner_player_stats.get_parent() if is_instance_valid(owner_player_stats) else null
		enemy_target.take_damage(final_damage, owner_player)
		
		# Apply Knockback
		var knockback_strength = float(specific_stats.get("knockback_strength", 150.0))
		if knockback_strength > 0 and enemy_target.has_method("apply_knockback"):
			# Knockback direction is always away from the player's center, not the bash's center
			var knockback_direction = (enemy_target.global_position - owner_player.global_position).normalized()
			enemy_target.apply_knockback(knockback_direction, knockback_strength)
