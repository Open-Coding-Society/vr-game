extends "res://scripts/missions/mission.gd"
## The script every "Build a Network" mission uses (Story IRL Act 4).
##
## mission.gd finishes a mission when every slot is filled. A network mission
## finishes when the *network* meets the mission's goal instead, e.g. "all
## three PCs reach each other", whichever of the switch's 8 ports the
## cables went into. So the ports are `optional` slots in data/modules.json,
## and the mission's "goal" there says what has to be true.
##
## It keeps one NetworkGraph (scripts/network/network_graph.gd): every device
## in the scene (scripts/network/network_device.gd) is in it, and every cable
## (scripts/parts/cable.gd) adds a link when both its ends are in ports and
## takes it away when one comes out. After each change it lights the ports,
## updates the PCs' screens and checks the goal: one small check per kind
## of goal, below.

const NetworkGraph := preload("res://scripts/network/network_graph.gd")
const NetworkDevice := preload("res://scripts/network/network_device.gd")

## The network changed: a cable went in or came out.
signal network_changed
## The redundancy check has cut every link in turn and shown the results.
signal cuts_tested(passed: bool)

## How long the redundancy check shows each cut (seconds). Tests set 0.
@export var cut_step_s := 0.8

var graph := NetworkGraph.new()
## Device id -> its node.
var devices: Dictionary = {}
## Port SnapZone -> its id in the graph ("pc_a:eth0"), and back.
var port_of: Dictionary = {}
var zone_of: Dictionary = {}
## The cables in the scene.
var cables: Array = []

## Whole messages that have arrived: "from>to" -> how many packets they had.
var delivered: Dictionary = {}
## cut_then_restore: the marked cable was pulled out, then the two devices
## were joined again, and packets arrived after that.
var was_cut := false
var restored := false
var arrived_since_restore := 0
## jobs_done: device id -> how many jobs are on it (connected machines only).
var job_counts: Dictionary = {}
## The goal was met and the mission is ending.
var finished := false
## Screens something else is writing on (a packet flow), by device id.
var screens_in_use: Dictionary = {}
## The redundancy check: what each cut did, one line per link, and whether
## it is running now.
var cut_report := PackedStringArray()
var testing_cuts := false
var _retest := false
## What the redundancy check last told the player, kept on the panel when a
## plug's own "Yes!" text comes after it.
var _cut_note := ""
## The scene's packets (scripts/network/packet_flow.gd, a child named
## PacketFlow), or null in a mission without them.
var flow: Node = null
## Distributed work: the job board (scripts/network/job_board.gd, a child
## named JobBoard) and each machine's Job slot by device id.
var job_board: Node = null
var job_zones: Dictionary = {}
## The device a machine must reach to get work (the switch the job comes from).
@export var job_host := "switch"


func _ready() -> void:
	super._ready()
	if config.is_empty():
		return
	_build_network()
	flow = find_child("PacketFlow", true, false)
	if flow:
		flow.setup(self)
		flow.packet_arrived.connect(func(from_id, to_id, _i) -> void: note_packet_arrived(from_id, to_id))
		flow.message_delivered.connect(func(from_id, to_id, packets, _text) -> void: note_delivered(from_id, to_id, packets))
	job_board = find_child("JobBoard", true, false)
	for id in devices:
		var job := devices[id].get_node_or_null("Job") as SnapZone
		if job and zones.has(job):
			job_zones[id] = job
			job.gate = func(_part) -> String: return "" if _on_network(id) else \
				"%s isn't on the network. Cable it to the switch first, then it can take work." % _name(id)
	for cable in cables:
		cable.plug_in_start_ports()
	var stream: Dictionary = config.get("stream", {})
	if flow and not stream.is_empty():
		flow.stream(stream.from, stream.to)
	_changed()


## Puts every device and port in the graph and listens to every cable.
func _build_network() -> void:
	for node in find_children("*", "StaticBody3D", true, false):
		if node.get_script() != NetworkDevice:
			continue
		if node.device_id == "" or devices.has(node.device_id):
			_problem('device "%s" needs a device_id of its own' % get_path_to(node))
			continue
		devices[node.device_id] = node
		graph.add_device(node.device_id, node.kind)
		for zone in node.ports():
			var id: String = node.port_id(zone)
			port_of[zone] = id
			zone_of[id] = zone
	for node in find_children("*", "Node3D", true, false):
		if node.has_signal("plugged") and node.has_method("plug_in_start_ports"):
			cables.append(node)
			node.plugged.connect(_on_cable_plugged)
			node.unplugged.connect(_on_cable_unplugged)
			_label_one_end(node)
	for id in goal_devices():
		if not devices.has(id):
			_problem('the goal names "%s", but no device in the scene has that device_id' % id)


## With many cables on a desk, a label over every plug is a pile of text: a
## cable's name shows over one loose end only (the first, if both are).
func _label_one_end(cable: Node) -> void:
	for end_name in ["EndA", "EndB"]:
		var end := cable.get_node_or_null(end_name)
		if end and end.has_signal("installed"):
			end.installed.connect(func(_part, _zone) -> void: _show_cable_label(cable))
			end.removed.connect(func(_part, _zone) -> void: _show_cable_label(cable))
	_show_cable_label(cable)


func _show_cable_label(cable: Node) -> void:
	var shown := false
	for end_name in ["EndA", "EndB"]:
		var end := cable.get_node_or_null(end_name)
		var tag := cable.get_node_or_null(end_name + "/Name") as Label3D
		if end and tag:
			tag.visible = not shown and not end.is_installed
			shown = shown or tag.visible


## Every device id the goal names.
func goal_devices() -> Array:
	var goal: Dictionary = config.get("goal", {})
	var out := []
	for key in goal:
		var value = goal[key]
		match key:
			"connected", "survives_any_single_cut", "from":
				out.append_array(value)
			"reach":
				out.append(value)
			"delivered":
				out.append_array([value.from, value.to])
			"cut_then_restore":
				out.append_array(value.map(func(p) -> String: return NetworkGraph.device_of(p)))
	return out


## A message card dropped into a device's Outbox (a part whose registry entry
## says who it is "to") is sent as packets.
func _on_snapped(zone: SnapZone, part: GrabbablePart) -> void:
	super(zone, part)
	if _cut_note != "" and not finished and manager.state == manager.State.ACTIVE:
		_show_checklist(_cut_note)
	var entry: Dictionary = config.parts.get(str(get_path_to(part)), {})
	var device := zone.get_parent()
	if entry.has("to") and flow and device.get_script() == NetworkDevice and manager.state == manager.State.ACTIVE:
		flow.send(device.device_id, entry.to, int(entry.get("packets", 4)), str(entry.get("text", "")))
	if job_zones.values().has(zone):
		_changed()


func _on_removed(zone: SnapZone, part: GrabbablePart) -> void:
	super(zone, part)
	if job_zones.values().has(zone):
		_changed()


func _on_cable_plugged(_cable: Node, zone_a: Area3D, zone_b: Area3D) -> void:
	if port_of.has(zone_a) and port_of.has(zone_b):
		note_plugged(port_of[zone_a], port_of[zone_b])


func _on_cable_unplugged(_cable: Node, zone_a: Area3D, zone_b: Area3D) -> void:
	if port_of.has(zone_a) and port_of.has(zone_b):
		note_unplugged(port_of[zone_a], port_of[zone_b])


## A cable now joins ports a and b ("pc_a:eth0").
func note_plugged(a: String, b: String) -> void:
	if not graph.connect_ports(a, b):
		return
	if was_cut and not restored and _cut_devices_joined():
		restored = true
		for port in _cut_ports():
			_show_port(port, "off")
	_show_port(a, "up")
	_show_port(b, "up")
	_changed()


## The cable that joined ports a and b came out.
func note_unplugged(a: String, b: String) -> void:
	graph.disconnect_ports(a, b)
	var cut := _is_cut_link(a, b) and not restored
	if cut:
		was_cut = true
	_show_port(a, "cut" if cut else "off")
	_show_port(b, "cut" if cut else "off")
	_changed()


## A whole message of `packets` packets arrived (scripts/network/packet_flow.gd).
func note_delivered(from_id: String, to_id: String, packets: int) -> void:
	var key := "%s>%s" % [from_id, to_id]
	delivered[key] = maxi(delivered.get(key, 0), packets)
	_changed()


## One packet arrived, of a message or a stream.
func note_packet_arrived(_from_id: String, _to_id: String) -> void:
	if restored:
		arrived_since_restore += 1
		_changed()


func _changed() -> void:
	_count_jobs()
	_update_screens()
	network_changed.emit()
	if manager == null:
		return  # not in a scene (a test checking the goals on their own)
	if config.get("goal", {}).has("survives_any_single_cut"):
		_redundancy_changed()
	elif not finished and manager.state == manager.State.ACTIVE:
		if goal_met():
			_finish()
		else:
			_show_checklist("")


func _finish() -> void:
	finished = true
	if flow:
		flow.stop_streams()
	if not job_zones.is_empty() and job_board and job_board.is_even(_all_job_counts()):
		manager.add_bonus(config.scoring.balanced_bonus)
	for z in zones:
		z.locked = true
	manager.complete()


# --- Distributed work ---------------------------------------------------------

## True when a machine can reach the device its work comes from.
func _on_network(id: String) -> bool:
	return not graph.path(id, job_host).is_empty()


## Jobs on each machine that is on the network, for the goal.
func _count_jobs() -> void:
	if job_zones.is_empty():
		return
	job_counts.clear()
	for id in job_zones:
		if _on_network(id):
			job_counts[id] = job_zones[id].installed_parts.size()
	if job_board:
		var all := _all_job_counts()
		var placed := 0
		for c in all:
			placed += c
		job_board.show_times(int(config.goal.get("jobs_done", placed)), job_counts.values(), placed)


## Jobs on every machine in the scene, on the network or not, in scene order.
func _all_job_counts() -> Array:
	return job_zones.values().map(func(z) -> int: return z.installed_parts.size())


func _result_extras() -> PackedStringArray:
	var out := PackedStringArray()
	if job_board and not job_zones.is_empty():
		out.append(job_board.summary(int(config.goal.jobs_done), job_counts.values()))
		if job_board.is_even(_all_job_counts()):
			out.append("Spread evenly across every machine: +%d" % config.scoring.balanced_bonus)
		else:
			out.append("Spread the tiles evenly across all the machines for %d more points." % config.scoring.balanced_bonus)
	return out


# --- The redundancy check -----------------------------------------------------

## Once the devices are all connected, the game tests the network for real:
## it cuts each link in turn (its lights go red), says what that cut did,
## and puts it back. If no one cut splits them, the mission is done.
func _redundancy_changed() -> void:
	if finished or manager.state != manager.State.ACTIVE:
		return
	var ids: Array = config.goal.survives_any_single_cut
	_cut_note = ""
	if not graph.all_connected(ids):
		cut_report.clear()
		_show_checklist("")
		return
	if testing_cuts:
		_retest = true
		return
	_test_cuts(ids)


func _test_cuts(ids: Array) -> void:
	testing_cuts = true
	cut_report.clear()
	var passed := true
	for result in graph.cut_results(ids, true):
		_show_port(result.a, "cut")
		_show_port(result.b, "cut")
		var what := "still connected" if result.ok else "%s cut off" % _names(result.cut_off)
		cut_report.append("%s %s: %s" % ["[x]" if result.ok else "[  ]", _link_name(result.a, result.b), what])
		passed = passed and result.ok
		_show_checklist("Testing: cutting each cable in turn...")
		if cut_step_s > 0.0:
			await get_tree().create_timer(cut_step_s).timeout
			if not is_inside_tree():
				return
		_show_port(result.a, "up" if graph.is_link_up(result.a, result.b) else "off")
		_show_port(result.b, "up" if graph.is_link_up(result.a, result.b) else "off")
	testing_cuts = false
	if _retest:
		# The network changed while it was being tested: test it again.
		_retest = false
		_redundancy_changed()
		return
	passed = passed and _goal_survives_any_single_cut(ids)
	cuts_tested.emit(passed)
	if passed:
		_finish()
	else:
		_cut_note = "One cut still splits the network. Add a second path around it."
		_show_checklist(_cut_note)


## "Switch 1 port 8 to Switch 2 port 8".
func _link_name(a: String, b: String) -> String:
	var za: Area3D = zone_of.get(a)
	var zb: Area3D = zone_of.get(b)
	return "%s to %s" % [za.display_name if za else a, zb.display_name if zb else b]


# --- The goals: one small check for each kind --------------------------------

## True when the network meets the mission's goal.
func goal_met() -> bool:
	var goal: Dictionary = config.get("goal", {})
	if goal.has("connected"):
		return _goal_connected(goal.connected)
	if goal.has("reach"):
		return _goal_reach(goal.reach, goal.from)
	if goal.has("delivered"):
		return _goal_delivered(goal.delivered)
	if goal.has("cut_then_restore"):
		return _goal_cut_then_restore()
	if goal.has("survives_any_single_cut"):
		return _goal_survives_any_single_cut(goal.survives_any_single_cut)
	if goal.has("jobs_done"):
		return _goal_jobs_done(goal.jobs_done, goal.get("min_machines", 1))
	return false


## Every one of `ids` reaches every other.
func _goal_connected(ids: Array) -> bool:
	return graph.all_connected(ids)


## Each of `from_ids` has a way to `target`.
func _goal_reach(target: String, from_ids: Array) -> bool:
	return from_ids.all(func(id) -> bool: return not graph.path(id, target).is_empty())


## A whole message of at least `need.packets` packets went from need.from to need.to.
func _goal_delivered(need: Dictionary) -> bool:
	return delivered.get("%s>%s" % [need.from, need.to], 0) >= int(need.packets)


## The marked cable was pulled, the devices were joined again, and packets
## got through after that.
func _goal_cut_then_restore() -> bool:
	return was_cut and restored and arrived_since_restore > 0


## No one cable's cut splits `ids` (a PC's own, only cable isn't tested:
## see NetworkGraph.survives_any_single_cut).
func _goal_survives_any_single_cut(ids: Array) -> bool:
	return graph.survives_any_single_cut(ids, true)


## At least `count` jobs are done, on at least `min_machines` machines.
func _goal_jobs_done(count: int, min_machines: int) -> bool:
	var total := 0
	var used := 0
	for id in job_counts:
		total += job_counts[id]
		if job_counts[id] > 0:
			used += 1
	return total >= count and used >= min_machines


# --- What the player sees -----------------------------------------------------

## The checklist: what the goal needs, ticked as it comes true.
func _status_lines() -> PackedStringArray:
	var goal: Dictionary = config.get("goal", {})
	var out := PackedStringArray()
	if goal.has("connected"):
		# Slots that must be filled first (a rack's bays) come before the goal.
		out.append_array(super._status_lines())
		out.append(_tick(_goal_connected(goal.connected)) + "%s can reach each other" % _names(goal.connected))
	elif goal.has("reach"):
		for id in goal.from:
			out.append(_tick(_goal_reach(goal.reach, [id])) + "%s reaches the %s" % [_name(id), _name(goal.reach)])
	elif goal.has("delivered"):
		var d: Dictionary = goal.delivered
		out.append(_tick(_goal_delivered(d)) + "The message gets from %s to %s" % [_name(d.from), _name(d.to)])
	elif goal.has("cut_then_restore"):
		out.append(_tick(was_cut) + "Pull out the marked cable")
		out.append(_tick(restored) + "Plug it back in")
		out.append(_tick(_goal_cut_then_restore()) + "Packets flow again")
	elif goal.has("survives_any_single_cut"):
		var ids: Array = goal.survives_any_single_cut
		out.append(_tick(graph.all_connected(ids)) + "%s are connected" % _names(ids))
		out.append(_tick(finished) + "They stay connected when any one cable is cut")
		out.append_array(cut_report)
	elif goal.has("jobs_done"):
		var total := 0
		var used := 0
		for id in job_counts:
			total += job_counts[id]
			used += 1 if job_counts[id] > 0 else 0
		var need_machines: int = goal.get("min_machines", 1)
		out.append(_tick(total >= goal.jobs_done) + "Jobs done: %d of %d" % [total, goal.jobs_done])
		out.append(_tick(used >= need_machines) + "Machines working: %d (at least %d)" % [used, need_machines])
	return out


## Each PC's screen says what it can reach: "PC B found", "Internet: online".
func _update_screens() -> void:
	for id in devices:
		var device: Node = devices[id]
		var screen: Node = device.screen()
		if screen == null or screens_in_use.has(id):
			continue
		var found := PackedStringArray()
		var online := false
		for other in graph.reachable(id):
			var kind: String = graph.devices[other]
			if kind == "internet":
				online = true
			elif kind in ["pc", "server"]:
				found.append(_name(other))
		var lines := PackedStringArray()
		if found.is_empty() and not online:
			lines.append("Network: not connected")
		elif not found.is_empty():
			lines.append("%s found" % name_list(Array(found)))
		if online:
			lines.append("Internet: online")
		screen.show_desktop(device.display_name, lines)


func _show_port(port: String, state: String) -> void:
	var zone: Area3D = zone_of.get(port)
	if zone:
		devices[NetworkGraph.device_of(port)].set_port_state(zone, state)


## The marked cable's two ports (cut_then_restore), or [].
func _cut_ports() -> Array:
	return config.get("goal", {}).get("cut_then_restore", [])


func _is_cut_link(a: String, b: String) -> bool:
	var marked := _cut_ports()
	return marked.size() == 2 and ((marked[0] == a and marked[1] == b) or (marked[0] == b and marked[1] == a))


## The two devices the marked cable joined have a way to each other again
## (back in the same ports, or in others).
func _cut_devices_joined() -> bool:
	var marked := _cut_ports()
	return marked.size() == 2 and not graph.path(NetworkGraph.device_of(marked[0]), NetworkGraph.device_of(marked[1])).is_empty()


## A device's name for the player ("PC A"), or its id when it has none.
func _name(id: String) -> String:
	var device: Node = devices.get(id)
	return device.display_name if device and device.display_name != "" else id


## "PC A and PC B", "PC A, PC B and PC C".
func _names(ids: Array) -> String:
	var names := ids.map(func(id) -> String: return _name(id))
	if names.size() <= 1:
		return "".join(names)
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names.back()]


static func _tick(done: bool) -> String:
	return "[x] " if done else "[  ] "
