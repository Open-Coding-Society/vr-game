extends SceneTree
## Checks for Phase 3, "Build a Network" (Story IRL Act 4): the network as
## data, the devices, the network missions, packets and the job board. Run
## from the project folder:
##
##   godot --headless --script res://tests/run_network_tests.gd
##
## Exit code 0 means every check passed. Like the other suites, mission tests
## load real scenes, move parts the way a grabber does and step physics.

const NetworkGraphScript := preload("res://scripts/network/network_graph.gd")
const ModuleRegistry := preload("res://scripts/module_registry.gd")
const TrainingManagerScript := preload("res://scripts/training_manager.gd")
const Cable := preload("res://scenes/parts/cable.tscn")
const SnapZone := preload("res://scripts/snap_zone.gd")
const GrabbablePart := preload("res://scripts/grabbable_part.gd")
const LinkLight := preload("res://scripts/parts/link_light.gd")

## Nodes under the root that stay between tests.
const AUTOLOADS := [&"TrainingManager", &"ScoreReporter", &"SaveService"]

var _failures: Array[String] = []
var manager: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Missions finished here would be recorded in the player's real save; use a
	# throwaway file instead.
	var saves := root.get_node_or_null("SaveService")
	if saves:
		saves.use_backend(preload("res://scripts/save/local_save_backend.gd").new("user://test_ocsvr_save.json"))
	manager = root.get_node_or_null("TrainingManager")
	if manager == null:
		manager = TrainingManagerScript.new()
		manager.name = "TrainingManager"
		root.add_child(manager)
	for test in _tests():
		manager.use_registry(ModuleRegistry.load_from())
		manager.now_ms = Time.get_ticks_msec
		manager.auto_advance = false
		await test.call()
	print("\n%s" % ("ALL PASSED" if _failures.is_empty() else "%d FAILED" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func _tests() -> Array:
	return [_test_graph_two_pcs, _test_graph_path_through_a_switch, _test_graph_disconnect,
		_test_graph_one_cable_per_port, _test_graph_pc_does_not_forward, _test_graph_link_down,
		_test_graph_internet_only_through_wan, _test_graph_bridges_line, _test_graph_bridges_ring,
		_test_graph_bridges_star, _test_graph_survives_any_single_cut, _test_graph_cut_results,
		_test_removable_slot, _test_fixed_slot_keeps_its_part, _test_locked_slot_keeps_its_part,
		_test_cable_plugged_signals, _test_removing_is_not_a_mistake, _test_link_light_goes_out]


func check(label: String, ok: bool, detail = "") -> void:
	var why := str(detail)
	print(("PASS  " if ok else "FAIL  ") + label + ("" if ok or why == "" else "   [%s]" % why))
	if not ok:
		_failures.append(label)


## Clears the last test's nodes, then adds `node` under the root.
func _fresh(node: Node) -> Node:
	for child in root.get_children():
		if not child.name in AUTOLOADS:
			child.queue_free()
	await process_frame
	root.add_child(node)
	await _settle()
	return node


func _settle(frames := 3) -> void:
	for i in frames:
		await physics_frame


# --- Step 1: the network as data ---------------------------------------------

## A graph with these devices, e.g. {"pc_a": "pc", "sw": "switch"}.
func _graph(kinds: Dictionary) -> NetworkGraphScript:
	var g := NetworkGraphScript.new()
	for id in kinds:
		g.add_device(id, kinds[id])
	return g


## Three PCs, each cabled to a port of one switch.
func _star() -> NetworkGraphScript:
	var g := _graph({"pc_a": "pc", "pc_b": "pc", "pc_c": "pc", "sw": "switch"})
	g.connect_ports("pc_a:eth0", "sw:port1")
	g.connect_ports("pc_b:eth0", "sw:port2")
	g.connect_ports("pc_c:eth0", "sw:port3")
	return g


func _test_graph_two_pcs() -> void:
	var g := _graph({"pc_a": "pc", "pc_b": "pc"})
	check("graph: two PCs with no cable have no path", g.path("pc_a", "pc_b").is_empty())
	check("graph: a cable between two PCs is accepted", g.connect_ports("pc_a:eth0", "pc_b:eth0"))
	check("graph: then each finds the other", g.path("pc_a", "pc_b") == ["pc_a", "pc_b"], g.path("pc_a", "pc_b"))
	check("graph: a device's path to itself is just itself", g.path("pc_a", "pc_a") == ["pc_a"])
	check("graph: no path to a device that isn't there", g.path("pc_a", "nobody").is_empty())


func _test_graph_path_through_a_switch() -> void:
	var g := _star()
	check("graph: a path runs PC -> switch -> PC", g.path("pc_a", "pc_c") == ["pc_a", "sw", "pc_c"], g.path("pc_a", "pc_c"))
	check("graph: every PC reaches the other two and the switch", g.reachable("pc_b").size() == 3, g.reachable("pc_b"))
	check("graph: all three are connected", g.all_connected(["pc_a", "pc_b", "pc_c"]))


func _test_graph_disconnect() -> void:
	var g := _star()
	g.disconnect_ports("sw:port3", "pc_c:eth0")
	check("graph: no path after the cable is pulled (either end named first)", g.path("pc_a", "pc_c").is_empty())
	check("graph: the others still reach each other", g.path("pc_a", "pc_b").size() == 3)
	check("graph: the freed port can take a cable again", g.connect_ports("pc_c:eth0", "sw:port8"))
	check("graph: and the path is back", g.path("pc_a", "pc_c").size() == 3)


func _test_graph_one_cable_per_port() -> void:
	var g := _star()
	check("graph: a port that has a cable takes no second one", not g.connect_ports("pc_a:eth0", "sw:port4"))
	check("graph: nor does the switch port", not g.connect_ports("sw:port1", "pc_b:eth1"))
	check("graph: a cable can't join a port to itself", not g.connect_ports("sw:port5", "sw:port5"))
	check("graph: the refused cables were not added", g.links.size() == 3, g.links.size())


func _test_graph_pc_does_not_forward() -> void:
	# pc_a - pc_b - pc_c, with pc_b holding two cables.
	var g := _graph({"pc_a": "pc", "pc_b": "pc", "pc_c": "pc"})
	g.connect_ports("pc_a:eth0", "pc_b:eth0")
	g.connect_ports("pc_b:eth1", "pc_c:eth0")
	check("graph: a PC in the middle doesn't pass data on", g.path("pc_a", "pc_c").is_empty(), g.path("pc_a", "pc_c"))
	check("graph: but each end still reaches it", g.path("pc_a", "pc_b").size() == 2 and g.path("pc_c", "pc_b").size() == 2)
	var s := _graph({"pc_a": "pc", "srv": "server", "pc_c": "pc"})
	s.connect_ports("pc_a:eth0", "srv:eth0")
	s.connect_ports("srv:eth1", "pc_c:eth0")
	check("graph: nor does a server", s.path("pc_a", "pc_c").is_empty())


func _test_graph_link_down() -> void:
	var g := _star()
	g.set_link_up("pc_c:eth0", "sw:port3", false)
	check("graph: a link that is down carries nothing", g.path("pc_a", "pc_c").is_empty())
	check("graph: it is still plugged in", g.port_in_use("pc_c:eth0") and not g.is_link_up("sw:port3", "pc_c:eth0"))
	g.set_link_up("sw:port3", "pc_c:eth0", true)
	check("graph: back up, data flows again", g.path("pc_a", "pc_c").size() == 3)


func _test_graph_internet_only_through_wan() -> void:
	var g := _star()
	g.add_device("router", "router")
	g.add_device("internet", "internet")
	g.connect_ports("sw:port8", "router:lan1")
	g.connect_ports("router:lan2", "internet:jack")
	check("graph: the internet isn't reached through a LAN port", g.path("pc_a", "internet").is_empty())
	g.disconnect_ports("router:lan2", "internet:jack")
	g.connect_ports("router:wan", "internet:jack")
	check("graph: through the WAN port it is", g.path("pc_a", "internet") == ["pc_a", "sw", "router", "internet"], g.path("pc_a", "internet"))
	var h := _graph({"pc_a": "pc", "internet": "internet"})
	h.connect_ports("pc_a:eth0", "internet:jack")
	check("graph: a PC plugged straight into the wall jack isn't online", h.path("pc_a", "internet").is_empty())


## pc_a - sw1 - sw2 - pc_b: every cable is a single point of failure.
func _line() -> NetworkGraphScript:
	var g := _graph({"pc_a": "pc", "pc_b": "pc", "sw1": "switch", "sw2": "switch"})
	g.connect_ports("pc_a:eth0", "sw1:port1")
	g.connect_ports("sw1:port2", "sw2:port1")
	g.connect_ports("sw2:port2", "pc_b:eth0")
	return g


## Three switches in a ring, each with a PC.
func _ring() -> NetworkGraphScript:
	var g := _graph({"pc_a": "pc", "pc_b": "pc", "pc_c": "pc", "sw1": "switch", "sw2": "switch", "sw3": "switch"})
	g.connect_ports("sw1:port1", "sw2:port1")
	g.connect_ports("sw2:port2", "sw3:port1")
	g.connect_ports("sw3:port2", "sw1:port2")
	g.connect_ports("pc_a:eth0", "sw1:port3")
	g.connect_ports("pc_b:eth0", "sw2:port3")
	g.connect_ports("pc_c:eth0", "sw3:port3")
	return g


func _test_graph_bridges_line() -> void:
	check("graph: in a line every cable is a bridge", _line().bridges().size() == 3, _line().bridges())


func _test_graph_bridges_ring() -> void:
	var b := _ring().bridges()
	check("graph: in a ring only the PCs' own cables are bridges", b.size() == 3, b)
	check("graph: none of the switch-to-switch cables is", not b.any(func(p) -> bool: return p[0].begins_with("sw") and p[1].begins_with("sw")), b)


func _test_graph_bridges_star() -> void:
	check("graph: in a star every cable is a bridge", _star().bridges().size() == 3)
	var g := _graph({"pc_a": "pc", "pc_b": "pc"})
	check("graph: no cables, no bridges", g.bridges().is_empty())


func _test_graph_survives_any_single_cut() -> void:
	var switches := ["sw1", "sw2", "sw3"]
	check("graph: a ring of switches survives any one cut", _ring().survives_any_single_cut(switches))
	check("graph: a line doesn't", not _line().survives_any_single_cut(["sw1", "sw2", "pc_a"]))
	# Two cables between the same two switches: a second path.
	var g := _line()
	g.connect_ports("sw1:port3", "sw2:port3")
	check("graph: a second cable between two switches is a second path", g.survives_any_single_cut(["sw1", "sw2"]))
	var apart := _graph({"pc_a": "pc", "pc_b": "pc"})
	check("graph: devices that aren't connected at all don't pass", not apart.survives_any_single_cut(["pc_a", "pc_b"]))


func _test_graph_cut_results() -> void:
	var g := _line()
	var r := g.cut_results(["pc_a", "pc_b"])
	check("graph: cut_results has one entry per working link", r.size() == 3, r.size())
	check("graph: in a line each cut fails", r.all(func(x) -> bool: return not x.ok))
	check("graph: cutting leaves every link up afterwards", g.links.all(func(l) -> bool: return l.up))


# --- Step 2: removable slots and cables that tell the network ---------------

## A port made in code: a SnapZone at `at` that takes parts of `type`.
func _port(parent: Node3D, port_name: String, type: String, at: Vector3, removable := true) -> SnapZone:
	var zone := Area3D.new()
	zone.set_script(SnapZone)
	zone.name = port_name
	zone.position = at
	zone.accepts = StringName(type)
	zone.display_name = port_name
	zone.removable = removable
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.06, 0.06, 0.06)
	shape.shape = box
	zone.add_child(shape)
	parent.add_child(zone)
	return zone


## A bench with one Ethernet cable and two ports for it.
func _bench(removable := true) -> Array:
	var bench := Node3D.new()
	bench.name = "Bench"
	var cable := Cable.instantiate()
	cable.end_a_position = Vector3(-0.2, 0.0, 0.0)
	cable.end_b_position = Vector3(0.2, 0.0, 0.0)
	bench.add_child(cable)
	await _fresh(bench)
	for end_name in ["EndA", "EndB"]:
		(cable.get_node(end_name) as GrabbablePart).part_type = &"ethernet"
	var p1 := _port(bench, "Port1", "ethernet", Vector3(-0.1, 0.0, -0.3), removable)
	var p2 := _port(bench, "Port2", "ethernet", Vector3(0.1, 0.0, -0.3), removable)
	await _settle()
	return [bench, cable, p1, p2]


## Picks a part up, carries it to `to` and lets go, as a grabber does.
func _carry_and_drop(part: GrabbablePart, to: Vector3) -> void:
	part.grab()
	part.global_position = to
	await _settle()
	part.drop()
	await _settle()


func _test_removable_slot() -> void:
	var made := await _bench()
	var cable: Node3D = made[1]
	var p1: SnapZone = made[2]
	var p2: SnapZone = made[3]
	var a: GrabbablePart = cable.get_node("EndA")
	var removed := []
	p1.removed.connect(func(zone, part) -> void: removed.append([zone, part]))
	await _carry_and_drop(a, p1.global_position)
	check("removable: a plug goes into the port", a.is_installed and p1.is_filled() and a.installed_zone == p1)
	check("removable: and can still be grabbed", a.can_grab())
	check("removable: grabbing it pulls it out", a.grab() and not a.is_installed and not p1.is_filled())
	check("removable: the port says it was emptied", removed.size() == 1 and removed[0][1] == a, removed)
	a.global_position = p2.global_position
	await _settle()
	a.drop()
	await _settle()
	check("removable: the plug can go into another port", a.is_installed and p2.installed_part == a and not p1.is_filled())


func _test_fixed_slot_keeps_its_part() -> void:
	var made := await _bench(false)
	var cable: Node3D = made[1]
	var p1: SnapZone = made[2]
	var a: GrabbablePart = cable.get_node("EndA")
	await _carry_and_drop(a, p1.global_position)
	check("not removable: an installed plug can't be grabbed", a.is_installed and not a.can_grab() and not a.grab())
	check("not removable: the port stays full", p1.installed_part == a)


func _test_locked_slot_keeps_its_part() -> void:
	var made := await _bench()
	var cable: Node3D = made[1]
	var p1: SnapZone = made[2]
	var a: GrabbablePart = cable.get_node("EndA")
	await _carry_and_drop(a, p1.global_position)
	p1.locked = true
	check("removable but locked (the mission is over): it stays in", not a.can_grab())


func _test_cable_plugged_signals() -> void:
	var made := await _bench()
	var cable: Node3D = made[1]
	var p1: SnapZone = made[2]
	var p2: SnapZone = made[3]
	var events := []
	cable.plugged.connect(func(_c, x, y) -> void: events.append(["plugged", x, y]))
	cable.unplugged.connect(func(_c, x, y) -> void: events.append(["unplugged", x, y]))
	var a: GrabbablePart = cable.get_node("EndA")
	var b: GrabbablePart = cable.get_node("EndB")
	await _carry_and_drop(a, p1.global_position)
	check("cable: one end in isn't plugged yet", events.is_empty() and not cable.is_plugged())
	await _carry_and_drop(b, p2.global_position)
	check("cable: both ends in says plugged, with both ports", events.size() == 1 and events[0] == ["plugged", p1, p2], events)
	a.grab()
	check("cable: pulling an end out says unplugged, with the ports it joined", events.size() == 2 and events[1] == ["unplugged", p1, p2], events)
	a.global_position = Vector3(0, 0.5, 0.5)
	await _settle()
	a.drop()
	await _settle()
	check("cable: and it is no longer plugged", not cable.is_plugged() and cable.port_a == null and cable.port_b == p2)


func _test_removing_is_not_a_mistake() -> void:
	var mission := Node3D.new()
	# A real mission scene with a removable slot comes in step 5; here, the
	# rule itself: TrainingManager only counts mistakes it is told about, and
	# a zone pulling a part out emits removed, never rejected or blocked.
	var made := await _bench()
	var cable: Node3D = made[1]
	var p1: SnapZone = made[2]
	var bad := [0]
	p1.rejected.connect(func(_z, _p) -> void: bad[0] += 1)
	p1.blocked.connect(func(_z, _p) -> void: bad[0] += 1)
	var a: GrabbablePart = cable.get_node("EndA")
	await _carry_and_drop(a, p1.global_position)
	a.grab()
	await _carry_and_drop(a, p1.global_position)
	check("removing a plug and putting it back counts no mistake", bad[0] == 0 and a.is_installed)
	mission.free()


func _test_link_light_goes_out() -> void:
	var made := await _bench()
	var bench: Node3D = made[0]
	var cable: Node3D = made[1]
	var p1: SnapZone = made[2]
	var p2: SnapZone = made[3]
	var light := MeshInstance3D.new()
	light.set_script(LinkLight)
	light.zones = [NodePath("../Port1"), NodePath("../Port2")] as Array[NodePath]
	bench.add_child(light)
	await _settle()
	var a: GrabbablePart = cable.get_node("EndA")
	await _carry_and_drop(a, p1.global_position)
	await _carry_and_drop(cable.get_node("EndB"), p2.global_position)
	check("link light: green with both ends in", light.is_lit and light.shown_color() == light.on_color)
	a.grab()
	check("link light: dark again once an end is pulled out", not light.is_lit and light.shown_color() == light.off_color)
	light.set_cut(true)
	check("link light: red when the link is marked cut", light.shown_color() == light.cut_color)
	light.set_cut(false)
	a.drop()
