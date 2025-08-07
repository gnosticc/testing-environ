# BerserkerWave.gd
# An expanding area of effect that applies a temporary speed buff to any
# enemies it touches. Spawned by the OnDeathBehaviorHandler.
# VERSION 1.0

class_name BerserkerWave extends Area2D

var _radius: float = 200.0
var _buff_data: StatusEffectData
var _source_enemy: BaseEnemy # The enemy that created the wave, to avoid buffing itself.

# Keep track of who we've already buffed to avoid applying it multiple times.
var _hit_enemies: Array[BaseEnemy] = []

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready():
	body_entered.connect(_on_body_entered)
	
	# Ensure the collision shape is a circle
	if not collision_shape.shape is CircleShape2D:
		push_error("BerserkerWave requires its CollisionShape2D to have a CircleShape2D.")
		queue_free()
		return
		
	# Start scaled down to nothing.
	scale = Vector2.ZERO
	
	# Create a tween to handle the entire effect lifecycle.
	var tween = create_tween().set_parallel()
	
	# Tween the scale to expand the wave to its full size.
	tween.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	# Tween the modulate alpha to fade the sprite out over a longer duration.
	tween.tween_property(sprite, "modulate:a", 0.0, 1.0)
	
	# After the tween is finished, free the wave scene.
	tween.finished.connect(queue_free)

# Public function called by the OnDeathBehaviorHandler to set up the wave.
func initialize(p_radius: float, p_buff_data: StatusEffectData, p_source: BaseEnemy):
	_radius = p_radius
	_buff_data = p_buff_data
	_source_enemy = p_source
	
	# Set the collision shape's radius to match the data.
	(collision_shape.shape as CircleShape2D).radius = _radius
	
	# Scale the sprite to match the collision shape.
	var texture_size = sprite.texture.get_size()
	if texture_size.x > 0:
		sprite.scale = Vector2.ONE * (_radius * 2 / texture_size.x)

func _on_body_entered(body: Node2D):
	# Check if the body is a valid enemy that we haven't already hit.
	if body is BaseEnemy and body != _source_enemy and not body.is_dead() and not _hit_enemies.has(body):
		var enemy_to_buff = body as BaseEnemy
		if is_instance_valid(enemy_to_buff.status_effect_component):
			# Add to our list to prevent re-buffing.
			_hit_enemies.append(enemy_to_buff)
			# Apply the status effect. Your StatusEffectComponent should handle stacking/refreshing.
			enemy_to_buff.status_effect_component.apply_effect(_buff_data, _source_enemy)
