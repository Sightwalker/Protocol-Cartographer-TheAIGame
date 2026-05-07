extends Node2D

enum NodeType { SIGNAL, ENERGY, CACHE, HAZARD, KEY }

class NodeData:
	var id: int = -1
	var unit_pos: Vector2 = Vector2.ZERO
	var edges: Array[int] = []
	var node_type: int = 0
	var signal_value: int = 0
	var risk: int = 0
	var energy_gain: int = 0
	var memory_load: int = 0
	var uncertainty: float = 1.0
	var expected_value: float = 0.0
	var revealed: bool = false
	var simulated: bool = false
	var visited: bool = false


class Star:
	var npos: Vector2 = Vector2.ZERO
	var radius: float = 1.0
	var phase: float = 0.0
	var color: Color = Color.WHITE


class ActionPlan:
	var verb: String = "wait"
	var target: int = -1
	var reason: String = "idle"


const PANEL_MIN_WIDTH := 330.0
const PANEL_MAX_WIDTH := 405.0
const NODE_RADIUS := 13.0
const MAX_DEPTH := 5
const ACTION_NAMES: Array[String] = ["scan", "simulate", "commit", "compress", "fork"]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var elapsed: float = 0.0
var screen_size: Vector2 = Vector2(1280.0, 720.0)
var panel_width: float = 380.0
var board_rect: Rect2 = Rect2()
var panel_rect: Rect2 = Rect2()

var nodes: Array[NodeData] = []
var stars: Array[Star] = []
var logs: Array[String] = []
var policy_vector: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]

var auto_play: bool = true
var game_finished: bool = false
var finish_title: String = ""
var action_timer: float = 0.75
var turn: int = 0
var depth: int = 1
var insight: int = 0
var energy: int = 44
var coherence: int = 100
var entropy: float = 16.0
var memory_used: int = 0
var memory_cap: int = 24
var keys_integrated: int = 0
var current_id: int = 0
var selected_id: int = 0

var last_packet: String = ""
var pulse_message: String = ""
var pulse_timer: float = 0.0

var ui_layer: CanvasLayer
var header_label: Label
var stats_label: Label
var selected_label: Label
var packet_label: Label
var log_label: Label
var end_label: Label

var scan_button: Button
var simulate_button: Button
var commit_button: Button
var compress_button: Button
var fork_button: Button
var step_button: Button
var auto_button: Button
var reset_button: Button


func _ready() -> void:
	rng.randomize()
	_setup_ui()
	_refresh_layout(true)
	_generate_stars()
	_new_run()
	_update_ui()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and board_rect.has_point(mouse_event.position):
			var node_id: int = _node_at_position(mouse_event.position)
			if node_id != -1:
				selected_id = node_id
				_update_ui()

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return

		match key_event.keycode:
			KEY_A:
				_toggle_auto()
			KEY_SPACE:
				_step_ai()
			KEY_R:
				_new_run()
			KEY_1:
				_manual_action("scan")
			KEY_2:
				_manual_action("simulate")
			KEY_3:
				_manual_action("commit")
			KEY_4:
				_manual_action("compress")
			KEY_5:
				_manual_action("fork")


func _process(delta: float) -> void:
	elapsed += delta
	_refresh_layout()
	pulse_timer = max(0.0, pulse_timer - delta)

	if auto_play and not game_finished:
		action_timer -= delta
		if action_timer <= 0.0:
			_step_ai()
			action_timer = max(0.28, 0.92 - float(depth) * 0.06)

	_update_ui()
	queue_redraw()


func _setup_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	header_label = _make_label(24, Color(0.95, 0.98, 0.95))
	stats_label = _make_label(18, Color(0.84, 0.92, 0.93))
	selected_label = _make_label(17, Color(0.88, 0.86, 0.72))
	packet_label = _make_label(16, Color(0.71, 0.91, 0.88))
	log_label = _make_label(15, Color(0.68, 0.72, 0.75))
	end_label = _make_label(40, Color(0.98, 0.93, 0.72))
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	scan_button = _make_button("SCAN", "scan")
	simulate_button = _make_button("SIM", "simulate")
	commit_button = _make_button("COMMIT", "commit")
	compress_button = _make_button("COMPRESS", "compress")
	fork_button = _make_button("FORK", "fork")

	step_button = Button.new()
	step_button.text = "STEP AI"
	step_button.focus_mode = Control.FOCUS_NONE
	step_button.pressed.connect(Callable(self, "_step_ai"))
	ui_layer.add_child(step_button)

	auto_button = Button.new()
	auto_button.focus_mode = Control.FOCUS_NONE
	auto_button.pressed.connect(Callable(self, "_toggle_auto"))
	ui_layer.add_child(auto_button)

	reset_button = Button.new()
	reset_button.text = "RESET"
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(Callable(self, "_new_run"))
	ui_layer.add_child(reset_button)


func _make_label(font_size: int, font_color: Color) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_layer.add_child(label)
	return label


func _make_button(text: String, verb: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(Callable(self, "_manual_action").bind(verb))
	ui_layer.add_child(button)
	return button


func _refresh_layout(force: bool = false) -> void:
	var new_size: Vector2 = get_viewport_rect().size
	if not force and screen_size == new_size:
		return

	screen_size = new_size
	panel_width = clamp(screen_size.x * 0.31, PANEL_MIN_WIDTH, PANEL_MAX_WIDTH)
	panel_rect = Rect2(Vector2(screen_size.x - panel_width, 0.0), Vector2(panel_width, screen_size.y))
	board_rect = Rect2(Vector2(24.0, 24.0), Vector2(max(360.0, screen_size.x - panel_width - 54.0), max(360.0, screen_size.y - 48.0)))

	var px: float = panel_rect.position.x + 20.0
	var pw: float = panel_rect.size.x - 40.0
	header_label.position = Vector2(px, 18.0)
	header_label.size = Vector2(pw, 70.0)
	stats_label.position = Vector2(px, 94.0)
	stats_label.size = Vector2(pw, 112.0)
	selected_label.position = Vector2(px, 208.0)
	selected_label.size = Vector2(pw, 112.0)
	packet_label.position = Vector2(px, 326.0)
	packet_label.size = Vector2(pw, 154.0)
	log_label.position = Vector2(px, 484.0)
	log_label.size = Vector2(pw, max(80.0, screen_size.y - 716.0))
	end_label.position = board_rect.position
	end_label.size = board_rect.size

	var gap: float = 10.0
	var bw: float = (pw - gap) * 0.5
	var bh: float = 36.0
	var by: float = max(500.0, screen_size.y - 178.0)
	scan_button.position = Vector2(px, by)
	scan_button.size = Vector2(bw, bh)
	simulate_button.position = Vector2(px + bw + gap, by)
	simulate_button.size = Vector2(bw, bh)
	commit_button.position = Vector2(px, by + 44.0)
	commit_button.size = Vector2(bw, bh)
	compress_button.position = Vector2(px + bw + gap, by + 44.0)
	compress_button.size = Vector2(bw, bh)
	fork_button.position = Vector2(px, by + 88.0)
	fork_button.size = Vector2(bw, bh)
	step_button.position = Vector2(px + bw + gap, by + 88.0)
	step_button.size = Vector2(bw, bh)
	auto_button.position = Vector2(px, by + 132.0)
	auto_button.size = Vector2(bw, bh)
	reset_button.position = Vector2(px + bw + gap, by + 132.0)
	reset_button.size = Vector2(bw, bh)


func _generate_stars() -> void:
	stars.clear()
	for i in range(120):
		var star: Star = Star.new()
		star.npos = Vector2(rng.randf(), rng.randf())
		star.radius = rng.randf_range(0.7, 2.0)
		star.phase = rng.randf_range(0.0, TAU)
		if rng.randf() < 0.45:
			star.color = Color(0.56, 0.95, 0.82, 0.55)
		else:
			star.color = Color(0.95, 0.79, 0.48, 0.48)
		stars.append(star)


func _new_run() -> void:
	auto_play = true
	game_finished = false
	finish_title = ""
	turn = 0
	depth = 1
	insight = 0
	energy = 44
	coherence = 100
	entropy = 16.0
	memory_used = 0
	memory_cap = 24
	keys_integrated = 0
	action_timer = 0.5
	logs.clear()
	_log("boot: autonomous policy online")
	_generate_map()
	_set_packet("init", current_id, "seeded latent graph")
	pulse_message = "NEW PROTOCOL"
	pulse_timer = 1.4
	_update_ui()


func _generate_map() -> void:
	nodes.clear()
	var node_count: int = 25 + depth * 5

	for i in range(node_count):
		var node: NodeData = NodeData.new()
		node.id = i
		if i == 0:
			node.unit_pos = Vector2.ZERO
			node.node_type = NodeType.CACHE
			node.signal_value = 0
			node.risk = 0
			node.energy_gain = 0
			node.memory_load = 0
		else:
			node.unit_pos = _make_node_position()
			_assign_node_payload(node)
		nodes.append(node)

	_connect_graph()
	current_id = 0
	selected_id = 0
	nodes[0].revealed = true
	nodes[0].visited = true
	nodes[0].simulated = true
	_reveal_from(0, 3)
	var first_frontier: int = _best_scan_target()
	if first_frontier != -1:
		selected_id = first_frontier
	_compute_policy_vector()


func _make_node_position() -> Vector2:
	var candidate: Vector2 = Vector2.ZERO
	for attempt in range(64):
		var angle: float = rng.randf_range(0.0, TAU)
		var radius: float = sqrt(rng.randf_range(0.02, 1.0)) * 0.96
		candidate = Vector2(cos(angle), sin(angle)) * radius
		var clear: bool = true
		for other: NodeData in nodes:
			if other.unit_pos.distance_to(candidate) < 0.16:
				clear = false
				break
		if clear:
			return candidate
	return candidate


func _assign_node_payload(node: NodeData) -> void:
	var roll: float = rng.randf()
	if roll < 0.34:
		node.node_type = NodeType.SIGNAL
		node.signal_value = rng.randi_range(13, 27) + depth * 2
		node.risk = rng.randi_range(5, 22) + depth
		node.energy_gain = rng.randi_range(0, 4)
		node.memory_load = rng.randi_range(2, 5)
	elif roll < 0.51:
		node.node_type = NodeType.ENERGY
		node.signal_value = rng.randi_range(4, 11) + depth
		node.risk = rng.randi_range(4, 18) + depth
		node.energy_gain = rng.randi_range(13, 24) + depth * 2
		node.memory_load = rng.randi_range(1, 3)
	elif roll < 0.68:
		node.node_type = NodeType.CACHE
		node.signal_value = rng.randi_range(7, 16) + depth
		node.risk = rng.randi_range(3, 16) + depth
		node.energy_gain = rng.randi_range(0, 5)
		node.memory_load = -rng.randi_range(4, 9)
	elif roll < 0.89:
		node.node_type = NodeType.HAZARD
		node.signal_value = rng.randi_range(8, 20) + depth * 2
		node.risk = rng.randi_range(34, 64) + depth * 3
		node.energy_gain = rng.randi_range(-4, 5)
		node.memory_load = rng.randi_range(2, 6)
	else:
		node.node_type = NodeType.KEY
		node.signal_value = rng.randi_range(28, 44) + depth * 5
		node.risk = rng.randi_range(18, 42) + depth * 2
		node.energy_gain = rng.randi_range(2, 10)
		node.memory_load = rng.randi_range(4, 7)
	node.uncertainty = rng.randf_range(0.55, 1.0)
	node.expected_value = _commit_utility(node)


func _connect_graph() -> void:
	for i in range(nodes.size()):
		for k in range(3):
			var best_id: int = -1
			var best_distance: float = 999999.0
			for j in range(nodes.size()):
				if i == j or nodes[i].edges.has(j):
					continue
				var distance: float = nodes[i].unit_pos.distance_to(nodes[j].unit_pos)
				if distance < best_distance:
					best_distance = distance
					best_id = j
			if best_id != -1:
				_add_edge(i, best_id)

	for i in range(nodes.size()):
		if rng.randf() < 0.25:
			var extra: int = rng.randi_range(0, nodes.size() - 1)
			_add_edge(i, extra)


func _add_edge(a: int, b: int) -> void:
	if a == b:
		return
	if not nodes[a].edges.has(b):
		nodes[a].edges.append(b)
	if not nodes[b].edges.has(a):
		nodes[b].edges.append(a)


func _step_ai() -> void:
	if game_finished:
		return
	var plan: ActionPlan = _choose_ai_plan()
	_execute_plan(plan, true)


func _toggle_auto() -> void:
	auto_play = not auto_play
	_log("mode: auto %s" % ("on" if auto_play else "off"))
	_update_ui()


func _manual_action(verb: String) -> void:
	if game_finished:
		return
	auto_play = false
	var plan: ActionPlan = ActionPlan.new()
	plan.verb = verb
	plan.target = selected_id
	plan.reason = "manual packet"
	_execute_plan(plan, false)


func _choose_ai_plan() -> ActionPlan:
	_compute_policy_vector()
	var plan: ActionPlan = ActionPlan.new()
	var compress_score: float = policy_vector[3]
	var commit_target: int = _best_commit_target()
	var simulate_target: int = _best_simulate_target()
	var scan_target: int = _best_scan_target()

	if compress_score >= 0.86:
		plan.verb = "compress"
		plan.target = current_id
		plan.reason = "memory or entropy above comfort"
	elif commit_target != -1 and policy_vector[2] >= max(policy_vector[0], policy_vector[1]):
		plan.verb = "commit"
		plan.target = commit_target
		plan.reason = "best revealed frontier"
	elif simulate_target != -1 and policy_vector[1] >= 0.44:
		plan.verb = "simulate"
		plan.target = simulate_target
		plan.reason = "valuable uncertainty"
	elif scan_target != -1 and policy_vector[0] >= 0.28:
		plan.verb = "scan"
		plan.target = scan_target
		plan.reason = "frontier map incomplete"
	elif policy_vector[4] >= 0.34:
		plan.verb = "fork"
		plan.target = scan_target
		plan.reason = "parallel branch evaluation"
	else:
		plan.verb = "compress"
		plan.target = current_id
		plan.reason = "no dominant external move"

	return plan


func _compute_policy_vector() -> void:
	var frontier_total: int = _frontier_ids().size()
	var unrevealed_total: int = _unrevealed_frontier_ids().size()
	var revealed_total: int = _revealed_frontier_ids().size()
	var unsimulated_total: int = _unsimulated_frontier_ids().size()
	var commit_target: int = _best_commit_target()
	var commit_score: float = 0.0
	if commit_target != -1:
		commit_score = max(0.0, _commit_utility(nodes[commit_target]) / 55.0)

	var scan_score: float = clamp(float(unrevealed_total) / max(1.0, float(frontier_total)), 0.0, 1.0)
	var simulate_score: float = clamp(float(unsimulated_total) / max(1.0, float(revealed_total)) * 0.72, 0.0, 1.0)
	var compress_score: float = max(float(memory_used) / float(memory_cap), entropy / 100.0)
	var fork_score: float = 0.0
	if energy >= 12 and frontier_total >= 4:
		fork_score = clamp((float(frontier_total) - float(revealed_total)) / 8.0, 0.0, 1.0) * 0.72

	if energy < 4:
		scan_score *= 0.2
		simulate_score *= 0.1
		commit_score *= 0.5
		fork_score = 0.0

	policy_vector = [
		clamp(scan_score, 0.0, 1.0),
		clamp(simulate_score, 0.0, 1.0),
		clamp(commit_score, 0.0, 1.0),
		clamp(compress_score, 0.0, 1.0),
		clamp(fork_score, 0.0, 1.0)
	]


func _execute_plan(plan: ActionPlan, ai_controlled: bool) -> void:
	var accepted: bool = false
	var result: String = ""

	match plan.verb:
		"scan":
			accepted = _action_scan(plan.target)
			result = "revealed frontier"
		"simulate":
			accepted = _action_simulate(plan.target)
			result = "projected outcome"
		"commit":
			accepted = _action_commit(plan.target)
			result = "integrated node"
		"compress":
			accepted = _action_compress()
			result = "packed memory"
		"fork":
			accepted = _action_fork()
			result = "evaluated branches"
		_:
			result = "unknown verb"

	if not accepted:
		_set_packet(plan.verb, plan.target, "rejected: %s" % result)
		_log("reject: %s target %d" % [plan.verb, plan.target])
		if ai_controlled:
			var fallback: ActionPlan = ActionPlan.new()
			fallback.verb = "compress"
			fallback.target = current_id
			fallback.reason = "fallback after rejection"
			_execute_plan(fallback, false)
		return

	_set_packet(plan.verb, plan.target, "%s | %s" % [result, plan.reason])
	_after_turn()


func _action_scan(target: int) -> bool:
	if energy < 3:
		return false

	var revealed_count: int = 0
	if _is_valid_node(target) and _is_frontier(target) and not nodes[target].revealed:
		if _reveal_node(target):
			revealed_count += 1
	else:
		var picks: Array[int] = _best_scan_targets(3)
		for node_id: int in picks:
			if _reveal_node(node_id):
				revealed_count += 1

	if revealed_count <= 0:
		return false

	energy -= 3
	memory_used += revealed_count
	entropy += 1.2
	selected_id = target if _is_valid_node(target) else selected_id
	_log("scan: %d node(s) revealed" % revealed_count)
	pulse_message = "SCAN"
	pulse_timer = 0.55
	return true


func _action_simulate(target: int) -> bool:
	if energy < 4 or not _is_valid_node(target) or not _is_frontier(target):
		return false
	var node: NodeData = nodes[target]
	if not node.revealed or node.simulated:
		return false

	energy -= 4
	memory_used += 1
	entropy += 2.2
	node.simulated = true
	node.uncertainty = max(0.08, node.uncertainty * 0.35)
	node.expected_value = _commit_utility(node)
	selected_id = target
	_log("simulate: #%02d value %.1f" % [target, node.expected_value])
	pulse_message = "SIMULATE"
	pulse_timer = 0.55
	return true


func _action_commit(target: int) -> bool:
	if not _is_valid_node(target) or not _is_frontier(target):
		return false
	var node: NodeData = nodes[target]
	if not node.revealed:
		return false

	var energy_cost: int = 3 + int(round(float(max(0, node.risk)) / 28.0))
	if energy < energy_cost:
		return false

	var risk_roll: float = rng.randf_range(0.32, 0.86) if node.simulated else rng.randf_range(0.58, 1.18)
	var damage: int = int(round(float(node.risk) * risk_roll * 0.34))
	energy += node.energy_gain - energy_cost
	insight += node.signal_value
	coherence -= damage
	memory_used = max(0, memory_used + node.memory_load)
	entropy += node.uncertainty * 5.0 + float(node.risk) * 0.035
	node.visited = true
	node.simulated = true
	current_id = target
	selected_id = target

	if node.node_type == NodeType.KEY:
		keys_integrated += 1
		_log("commit: key #%02d integrated" % target)
	else:
		_log("commit: #%02d signal +%d risk %d" % [target, node.signal_value, damage])

	_reveal_from(target, 1)
	pulse_message = "COMMIT"
	pulse_timer = 0.65
	return true


func _action_compress() -> bool:
	var packed: int = min(memory_used, 7 + depth)
	var entropy_drop: float = 7.0 + float(packed) * 1.4
	energy = max(0, energy - 1)
	memory_used = max(0, memory_used - packed)
	entropy = max(0.0, entropy - entropy_drop)
	insight += packed * 2
	coherence = min(100, coherence + max(1, int(round(float(packed) * 0.45))))
	_log("compress: memory -%d entropy -%d" % [packed, int(round(entropy_drop))])
	pulse_message = "COMPRESS"
	pulse_timer = 0.55
	return true


func _action_fork() -> bool:
	if energy < 8:
		return false

	var targets: Array[int] = _best_fork_targets(3)
	if targets.is_empty():
		return false

	energy -= 8
	memory_used += 4
	entropy += 4.8
	for target: int in targets:
		_reveal_node(target)
		var node: NodeData = nodes[target]
		node.simulated = true
		node.uncertainty = max(0.08, node.uncertainty * 0.42)
		node.expected_value = _commit_utility(node)
	selected_id = targets[0]
	_log("fork: %d branches evaluated" % targets.size())
	pulse_message = "FORK"
	pulse_timer = 0.65
	return true


func _after_turn() -> void:
	turn += 1
	energy = clamp(energy, 0, 99)
	entropy += 1.0 + float(depth) * 0.22

	if memory_used > memory_cap:
		var overflow: int = memory_used - memory_cap
		coherence -= overflow * 2
		entropy += float(overflow) * 0.75
		_log("overflow: memory pressure %d" % overflow)

	if entropy >= 100.0:
		entropy = 68.0
		coherence -= 12 + depth * 2
		_log("entropy spike: coherence damaged")

	if energy <= 0:
		coherence -= 3
		_log("starvation: no energy reserve")

	if coherence <= 0:
		_finish("POLICY COLLAPSED")
		return

	if keys_integrated >= 2 or _frontier_ids().is_empty():
		_descend()

	_compute_policy_vector()


func _descend() -> void:
	if depth >= MAX_DEPTH:
		_finish("PROTOCOL STABILIZED")
		return

	depth += 1
	keys_integrated = 0
	memory_used = max(0, memory_used - 8)
	memory_cap += 3
	energy = min(72, energy + 18)
	coherence = min(100, coherence + 12)
	entropy = max(10.0, entropy - 38.0)
	_log("depth: entered layer %d" % depth)
	_generate_map()
	pulse_message = "DEPTH %d" % depth
	pulse_timer = 1.2


func _finish(title: String) -> void:
	game_finished = true
	auto_play = false
	finish_title = title
	_log("finish: %s" % title.to_lower())
	pulse_message = title
	pulse_timer = 2.0


func _reveal_from(node_id: int, count: int) -> void:
	if not _is_valid_node(node_id):
		return
	var revealed: int = 0
	for neighbor_id: int in nodes[node_id].edges:
		if revealed >= count:
			return
		if not nodes[neighbor_id].revealed:
			_reveal_node(neighbor_id)
			revealed += 1


func _reveal_node(node_id: int) -> bool:
	if not _is_valid_node(node_id):
		return false
	var node: NodeData = nodes[node_id]
	if node.revealed:
		return false
	node.revealed = true
	node.uncertainty = max(0.18, node.uncertainty * 0.58)
	return true


func _is_valid_node(node_id: int) -> bool:
	return node_id >= 0 and node_id < nodes.size()


func _is_frontier(node_id: int) -> bool:
	if not _is_valid_node(node_id) or nodes[node_id].visited:
		return false
	for neighbor_id: int in nodes[node_id].edges:
		if nodes[neighbor_id].visited:
			return true
	return false


func _frontier_ids() -> Array[int]:
	var ids: Array[int] = []
	for node: NodeData in nodes:
		if _is_frontier(node.id):
			ids.append(node.id)
	return ids


func _revealed_frontier_ids() -> Array[int]:
	var ids: Array[int] = []
	for node_id: int in _frontier_ids():
		if nodes[node_id].revealed:
			ids.append(node_id)
	return ids


func _unrevealed_frontier_ids() -> Array[int]:
	var ids: Array[int] = []
	for node_id: int in _frontier_ids():
		if not nodes[node_id].revealed:
			ids.append(node_id)
	return ids


func _unsimulated_frontier_ids() -> Array[int]:
	var ids: Array[int] = []
	for node_id: int in _revealed_frontier_ids():
		if not nodes[node_id].simulated:
			ids.append(node_id)
	return ids


func _best_scan_target() -> int:
	var best_id: int = -1
	var best_score: float = -99999.0
	for node_id: int in _unrevealed_frontier_ids():
		var node: NodeData = nodes[node_id]
		var score_value: float = float(node.edges.size()) + node.uncertainty * 2.0 - node.unit_pos.length() * 0.2
		if score_value > best_score:
			best_score = score_value
			best_id = node_id
	return best_id


func _best_scan_targets(limit: int) -> Array[int]:
	var chosen: Array[int] = []
	for i in range(limit):
		var best_id: int = -1
		var best_score: float = -99999.0
		for node_id: int in _unrevealed_frontier_ids():
			if chosen.has(node_id):
				continue
			var node: NodeData = nodes[node_id]
			var score_value: float = float(node.edges.size()) + node.uncertainty * 2.0
			if score_value > best_score:
				best_score = score_value
				best_id = node_id
		if best_id != -1:
			chosen.append(best_id)
	return chosen


func _best_simulate_target() -> int:
	var best_id: int = -1
	var best_score: float = -99999.0
	for node_id: int in _unsimulated_frontier_ids():
		var node: NodeData = nodes[node_id]
		var score_value: float = float(node.signal_value) + float(node.risk) * 0.8 + node.uncertainty * 16.0
		if score_value > best_score:
			best_score = score_value
			best_id = node_id
	return best_id


func _best_commit_target() -> int:
	var best_id: int = -1
	var best_score: float = -99999.0
	for node_id: int in _revealed_frontier_ids():
		var score_value: float = _commit_utility(nodes[node_id])
		if score_value > best_score:
			best_score = score_value
			best_id = node_id
	return best_id


func _best_fork_targets(limit: int) -> Array[int]:
	var chosen: Array[int] = []
	for i in range(limit):
		var best_id: int = -1
		var best_score: float = -99999.0
		for node_id: int in _frontier_ids():
			if chosen.has(node_id):
				continue
			var node: NodeData = nodes[node_id]
			var reveal_bonus: float = 12.0 if not node.revealed else 0.0
			var sim_bonus: float = 8.0 if not node.simulated else 0.0
			var score_value: float = _commit_utility(node) + reveal_bonus + sim_bonus
			if score_value > best_score:
				best_score = score_value
				best_id = node_id
		if best_id != -1:
			chosen.append(best_id)
	return chosen


func _commit_utility(node: NodeData) -> float:
	var type_bonus: float = 0.0
	if node.node_type == NodeType.KEY:
		type_bonus = 24.0
	elif node.node_type == NodeType.CACHE:
		type_bonus = 10.0
	elif node.node_type == NodeType.ENERGY and energy < 18:
		type_bonus = 16.0

	var risk_weight: float = 0.45 if node.simulated else 0.78
	var memory_penalty: float = float(max(0, node.memory_load)) * (2.2 if memory_used < memory_cap else 4.0)
	var energy_bonus: float = float(node.energy_gain) * (1.35 if energy < 22 else 0.7)
	return float(node.signal_value) + energy_bonus + type_bonus - float(node.risk) * risk_weight - memory_penalty


func _set_packet(verb: String, target: int, reason: String) -> void:
	last_packet = "{ \"turn\": %d,\n  \"verb\": \"%s\",\n  \"target\": %d,\n  \"reason\": \"%s\" }" % [turn, verb, target, reason]


func _log(line: String) -> void:
	logs.append("t%03d %s" % [turn, line])
	while logs.size() > 8:
		logs.remove_at(0)


func _update_ui() -> void:
	header_label.text = "PROTOCOL CARTOGRAPHER\nAI-native exploration"
	auto_button.text = "AUTO ON" if auto_play else "AUTO OFF"

	stats_label.text = "Depth %d/%d   Turn %d\nInsight %d   Energy %d\nCoherence %d%%   Entropy %d%%\nMemory %d/%d   Keys %d/2" % [
		depth, MAX_DEPTH, turn, insight, energy, max(0, coherence), int(round(entropy)), memory_used, memory_cap, keys_integrated
	]

	selected_label.text = _selected_text()
	packet_label.text = "%s\n\npolicy_vector\n%s" % [last_packet, _policy_text()]
	log_label.text = _log_text()
	end_label.text = _end_text()

	var disabled: bool = game_finished
	scan_button.disabled = disabled
	simulate_button.disabled = disabled
	commit_button.disabled = disabled
	compress_button.disabled = disabled
	fork_button.disabled = disabled
	step_button.disabled = disabled


func _selected_text() -> String:
	if not _is_valid_node(selected_id):
		return "selected: none"
	var node: NodeData = nodes[selected_id]
	var status: String = "visited" if node.visited else ("frontier" if _is_frontier(node.id) else "distant")
	var reveal: String = "hidden"
	if node.revealed:
		reveal = _node_type_name(node.node_type)
	var sim: String = "sim %.1f" % node.expected_value if node.simulated else "unsimulated"
	var payload: String = "latent"
	if node.revealed:
		payload = "sig %+d  risk %d  energy %+d  mem %+d" % [node.signal_value, node.risk, node.energy_gain, node.memory_load]
	return "selected #%02d  %s\n%s   %s\n%s" % [node.id, status, reveal, sim, payload]


func _policy_text() -> String:
	var text: String = ""
	for i in range(ACTION_NAMES.size()):
		var value: float = policy_vector[i]
		var bars: int = int(round(value * 12.0))
		var bar_text: String = ""
		for j in range(bars):
			bar_text += "#"
		text += "%s %.2f %s\n" % [ACTION_NAMES[i], value, bar_text]
	return text.strip_edges()


func _log_text() -> String:
	var text: String = ""
	for i in range(logs.size() - 1, -1, -1):
		text += logs[i] + "\n"
	return text.strip_edges()


func _end_text() -> String:
	if game_finished:
		return "%s\n\nInsight %d\nTurn %d" % [finish_title, insight, turn]
	if pulse_timer > 0.0:
		return pulse_message
	return ""


func _node_at_position(point: Vector2) -> int:
	var best_id: int = -1
	var best_distance: float = 999999.0
	for node: NodeData in nodes:
		var pos: Vector2 = _node_screen_pos(node)
		var distance: float = pos.distance_to(point)
		if distance < NODE_RADIUS * 1.7 and distance < best_distance:
			best_distance = distance
			best_id = node.id
	return best_id


func _node_screen_pos(node: NodeData) -> Vector2:
	var radius: float = min(board_rect.size.x, board_rect.size.y) * 0.47
	return board_rect.position + board_rect.size * 0.5 + node.unit_pos * radius


func _node_type_name(node_type: int) -> String:
	match node_type:
		NodeType.SIGNAL:
			return "signal"
		NodeType.ENERGY:
			return "energy"
		NodeType.CACHE:
			return "cache"
		NodeType.HAZARD:
			return "hazard"
		NodeType.KEY:
			return "key"
	return "unknown"


func _node_color(node: NodeData) -> Color:
	if not node.revealed:
		return Color(0.16, 0.18, 0.19, 1.0)
	match node.node_type:
		NodeType.SIGNAL:
			return Color(0.35, 0.95, 0.62, 1.0)
		NodeType.ENERGY:
			return Color(1.0, 0.72, 0.28, 1.0)
		NodeType.CACHE:
			return Color(0.35, 0.74, 1.0, 1.0)
		NodeType.HAZARD:
			return Color(1.0, 0.22, 0.20, 1.0)
		NodeType.KEY:
			return Color(0.78, 0.56, 1.0, 1.0)
	return Color(0.8, 0.8, 0.8, 1.0)


func _draw() -> void:
	_draw_background()
	_draw_board()
	_draw_graph()
	_draw_attention()
	_draw_nodes()
	_draw_panel()


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.027, 0.028, 0.028), true)
	for star: Star in stars:
		var pos: Vector2 = Vector2(star.npos.x * screen_size.x, star.npos.y * screen_size.y)
		var color: Color = star.color
		color.a *= 0.68 + sin(elapsed * 1.6 + star.phase) * 0.24
		draw_circle(pos, star.radius, color)


func _draw_board() -> void:
	draw_rect(board_rect, Color(0.05, 0.058, 0.055, 0.88), true)
	draw_rect(board_rect, Color(0.38, 0.72, 0.63, 0.22), false, 1.5)
	var center: Vector2 = board_rect.position + board_rect.size * 0.5
	var radius: float = min(board_rect.size.x, board_rect.size.y) * 0.47
	for i in range(5):
		var ring_radius: float = radius * (0.24 + float(i) * 0.18)
		draw_arc(center, ring_radius, 0.0, TAU, 128, Color(0.33, 0.74, 0.61, 0.08 + float(i) * 0.018), 1.2)
	var entropy_alpha: float = clamp(entropy / 100.0, 0.0, 1.0) * 0.14
	draw_rect(board_rect, Color(0.82, 0.15, 0.13, entropy_alpha), true)


func _draw_graph() -> void:
	for node: NodeData in nodes:
		var a: Vector2 = _node_screen_pos(node)
		for neighbor_id: int in node.edges:
			if neighbor_id < node.id:
				continue
			var other: NodeData = nodes[neighbor_id]
			var b: Vector2 = _node_screen_pos(other)
			var edge_color: Color = Color(0.2, 0.26, 0.25, 0.34)
			if node.visited and other.visited:
				edge_color = Color(0.55, 0.95, 0.74, 0.55)
			elif node.revealed or other.revealed:
				edge_color = Color(0.44, 0.62, 0.57, 0.36)
			draw_line(a, b, edge_color, 1.3)


func _draw_attention() -> void:
	if _is_valid_node(current_id) and _is_valid_node(selected_id):
		var current_pos: Vector2 = _node_screen_pos(nodes[current_id])
		var selected_pos: Vector2 = _node_screen_pos(nodes[selected_id])
		draw_line(current_pos, selected_pos, Color(1.0, 0.86, 0.36, 0.42), 2.5)
		draw_circle(selected_pos, NODE_RADIUS * 2.2 + sin(elapsed * 4.0) * 2.0, Color(1.0, 0.86, 0.36, 0.08))


func _draw_nodes() -> void:
	for node: NodeData in nodes:
		var pos: Vector2 = _node_screen_pos(node)
		var radius: float = NODE_RADIUS
		if node.visited:
			radius += 3.5
		if node.id == current_id:
			radius += 4.0 + sin(elapsed * 5.0) * 1.2
		var color: Color = _node_color(node)
		var fill_alpha: float = 0.95 if node.revealed else 0.58
		if node.visited:
			fill_alpha = 1.0
		color.a = fill_alpha
		draw_circle(pos, radius + 7.0, Color(color.r, color.g, color.b, 0.08))
		draw_circle(pos, radius, color)
		var outline: Color = Color(0.85, 0.94, 0.86, 0.45)
		if node.id == selected_id:
			outline = Color(1.0, 0.91, 0.48, 0.95)
		elif node.simulated:
			outline = Color(0.72, 0.96, 1.0, 0.75)
		draw_arc(pos, radius + 4.0, 0.0, TAU, 40, outline, 2.0)
		_draw_node_glyph(node, pos, radius)


func _draw_node_glyph(node: NodeData, pos: Vector2, radius: float) -> void:
	if not node.revealed:
		draw_circle(pos, 3.0, Color(0.7, 0.74, 0.71, 0.6))
		return

	if node.node_type == NodeType.HAZARD:
		var tri: PackedVector2Array = PackedVector2Array([
			pos + Vector2(0.0, -radius * 0.48),
			pos + Vector2(radius * 0.48, radius * 0.36),
			pos + Vector2(-radius * 0.48, radius * 0.36)
		])
		draw_colored_polygon(tri, Color(0.12, 0.02, 0.02, 0.72))
	elif node.node_type == NodeType.KEY:
		var diamond: PackedVector2Array = PackedVector2Array([
			pos + Vector2(0.0, -radius * 0.52),
			pos + Vector2(radius * 0.52, 0.0),
			pos + Vector2(0.0, radius * 0.52),
			pos + Vector2(-radius * 0.52, 0.0)
		])
		draw_colored_polygon(diamond, Color(0.08, 0.04, 0.12, 0.72))
	elif node.node_type == NodeType.ENERGY:
		draw_rect(Rect2(pos - Vector2(radius * 0.34, radius * 0.34), Vector2(radius * 0.68, radius * 0.68)), Color(0.14, 0.09, 0.02, 0.74), true)
	elif node.node_type == NodeType.CACHE:
		draw_arc(pos, radius * 0.46, -PI * 0.2, PI * 1.2, 28, Color(0.04, 0.08, 0.12, 0.86), 3.0)
	else:
		draw_circle(pos, radius * 0.28, Color(0.03, 0.11, 0.06, 0.72))


func _draw_panel() -> void:
	draw_rect(panel_rect, Color(0.04, 0.043, 0.04, 0.96), true)
	draw_line(panel_rect.position, panel_rect.position + Vector2(0.0, panel_rect.size.y), Color(0.72, 0.78, 0.58, 0.25), 1.5)

	var px: float = panel_rect.position.x + 20.0
	var y: float = 462.0
	var bar_width: float = panel_rect.size.x - 40.0
	if screen_size.y < 660.0:
		return
	for i in range(ACTION_NAMES.size()):
		var value: float = policy_vector[i]
		var bar_rect: Rect2 = Rect2(Vector2(px, y + float(i) * 11.0), Vector2(bar_width * value, 5.0))
		draw_rect(Rect2(Vector2(px, y + float(i) * 11.0), Vector2(bar_width, 5.0)), Color(0.16, 0.18, 0.16, 1.0), true)
		draw_rect(bar_rect, Color(0.6, 0.94, 0.72, 0.78), true)
