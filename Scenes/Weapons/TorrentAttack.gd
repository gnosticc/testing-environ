extends Area2D

var final_damage_amount: int = 18
var final_applied_aoe_scale: Vector2 = Vector2(1.0, 1.0) 

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite") as AnimatedSprite2D
@onready var effect_lifetime_timer: Timer = get_node_or_null("EffectLifetimeTimer") as Timer 
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D 

const TORRENT_ANIMATION_NAME = "erupt" 
const MAX_EFFECT_DURATION: float = 2.0 
var actual_effect_duration: float = MAX_EFFECT_DURATION

var _enemies_hit_this_attack: Array[Node2D] = [] 
var _stats_have_been_set: bool = false
var _received_stats: Dictionary = {}

func _ready():
	if not self.is_connected("body_entered", Callable(self, "_on_body_entered")):
		self.body_entered.connect(self._on_body_entered)

	if not is_instance_valid(animated_sprite): print("WARNING (TorrentAttack): AnimatedSprite missing.")
	if not is_instance_valid(collision_shape): print("WARNING (TorrentAttack): CollisionShape2D missing.")
	
	if not is_instance_valid(effect_lifetime_timer): print("ERROR (TorrentAttack): EffectLifetimeTimer missing!"); call_deferred("queue_free"); return
	else:
		effect_lifetime_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		effect_lifetime_timer.one_shot = true 
		if not effect_lifetime_timer.is_connected("timeout", Callable(self, "queue_free")):
			effect_lifetime_timer.timeout.connect(self.queue_free)
	
	if _stats_have_been_set: _apply_all_stats_and_start_timers()
	else: _apply_visual_scale() 

	if is_instance_valid(animated_sprite):
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(TORRENT_ANIMATION_NAME):
			animated_sprite.play(TORRENT_ANIMATION_NAME) 
		else: print("WARNING (TorrentAttack): Animation '", TORRENT_ANIMATION_NAME, "' not found.")


func set_attack_properties(p_attack_stats: Dictionary): 
	_received_stats = p_attack_stats.duplicate(true)
	_stats_have_been_set = true
	if is_inside_tree(): _apply_all_stats_and_start_timers()

func _apply_all_stats_and_start_timers():
	if not _stats_have_been_set: return
	if not is_instance_valid(effect_lifetime_timer):
		print("ERROR (TorrentAttack): EffectLifetimeTimer not valid in _apply_all_stats_and_start_timers.")
		return

	var base_w_damage = _received_stats.get("damage", 18)
	var p_dmg_mult = _received_stats.get("damage_multiplier", 1.0)
	var p_flat_dmg = _received_stats.get("base_damage_bonus", 0.0)
	final_damage_amount = int(round(base_w_damage * p_dmg_mult + p_flat_dmg))
	
	var weapon_inherent_scl_val = _received_stats.get("inherent_visual_scale", Vector2(1.0, 1.0))
	var weapon_inherent_base_scale: Vector2
	if weapon_inherent_scl_val is Vector2: weapon_inherent_base_scale = weapon_inherent_scl_val
	elif weapon_inherent_scl_val is float: weapon_inherent_base_scale = Vector2(weapon_inherent_scl_val, weapon_inherent_scl_val)
	else: weapon_inherent_base_scale = Vector2(1.0, 1.0)
	
	var p_aoe_mult = _received_stats.get("aoe_area_multiplier", 1.0) 
	final_applied_aoe_scale.x = weapon_inherent_base_scale.x * p_aoe_mult
	final_applied_aoe_scale.y = weapon_inherent_base_scale.y * p_aoe_mult
	
	var p_effect_dur_mult = _received_stats.get("effect_duration_multiplier", 1.0)
	var base_effect_duration = _received_stats.get("base_effect_duration", MAX_EFFECT_DURATION) 
	actual_effect_duration = base_effect_duration * p_effect_dur_mult 
	
	effect_lifetime_timer.wait_time = actual_effect_duration 
	if not effect_lifetime_timer.is_stopped(): effect_lifetime_timer.stop()
	effect_lifetime_timer.start()

	var attack_speed_multiplier = _received_stats.get("attack_speed_multiplier", 1.0) 
	if attack_speed_multiplier <= 0: attack_speed_multiplier = 0.01
	if is_instance_valid(animated_sprite): 
		animated_sprite.speed_scale = attack_speed_multiplier
		if not animated_sprite.is_playing() and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(TORRENT_ANIMATION_NAME):
			animated_sprite.play(TORRENT_ANIMATION_NAME)
	
	_apply_visual_scale()

func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_aoe_scale
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_aoe_scale

func _on_body_entered(body: Node2D):
	if is_instance_valid(effect_lifetime_timer) and effect_lifetime_timer.is_stopped(): return 
	if body.is_in_group("enemies") and not _enemies_hit_this_attack.has(body): 
		if body.has_method("take_damage"): body.take_damage(final_damage_amount)
		_enemies_hit_this_attack.append(body) 
