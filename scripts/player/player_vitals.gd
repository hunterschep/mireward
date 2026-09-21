class_name PlayerVitals
extends RefCounted

var since_spend: float = 0.0

func spend_stamina(amount: float) -> bool:
	if amount <= 0 or GameSession.state.player.stamina < amount:
		return false
	GameSession.state.player.stamina -= amount
	since_spend = 0.0
	return true

func drain_sprint(delta: float) -> void:
	GameSession.state.player.stamina = maxf(0.0, float(GameSession.state.player.stamina) - 12.0 * delta)
	since_spend = 0.0

func advance(delta: float, regeneration_suspended: bool) -> void:
	since_spend += delta
	if not regeneration_suspended and since_spend >= 0.8:
		GameSession.state.player.stamina = minf(100.0, float(GameSession.state.player.stamina) + 22.0 * delta)

func reset() -> void:
	since_spend = 0.0
