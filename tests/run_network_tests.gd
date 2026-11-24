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
const NetworkDevice := preload("res://scripts/network/network_device.gd")
const Cat6Cable := preload("res://scenes/network/cat6_cable.tscn")
const NetworkMission := preload("res://scripts/missions/network_mission.gd")
const GoOnline := preload("res://scenes/setup_pc/go_online.tscn")

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
		_test_cable_plugged_signals, _test_removing_is_not_a_mistake, _test_link_light_goes_out,
		_test_device_ports, _test_device_port_ids, _test_device_port_lights, _test_device_other_slots,
		_test_pc_has_a_screen, _test_cat6_cable,
		_test_goal_connected, _test_goal_reach, _test_goal_delivered, _test_goal_cut_then_restore,
		_test_goal_survives_any_single_cut, _test_goal_jobs_done, _test_registry_checks_goals,
		_test_registry_optional_slots, _test_optional_slot_is_not_needed, _test_old_mission_finishes_the_old_way,
		_test_goal_mission_ignores_full_slots, _test_cable_start_ports,
		_test_build_network_is_in_the_registry, _test_network_scenes_load, _test_connect_two,
		_test_connect_two_power_socket_is_a_mistake, _test_unplugging_in_a_mission, _test_switch_any_ports,
		_test_router_starts_cabled, _test_router_wan_lan_swapped, _test_router_perfect_run]


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


# --- Step 3: the devices ------------------------------------------------------

## Each device scene: its kind and its network ports, in order.
const DEVICES := {
	"res://scenes/network/devices/pc.tscn": ["pc", ["Eth0"]],
	"res://scenes/network/devices/mac_mini.tscn": ["pc", ["Eth0"]],
	"res://scenes/network/devices/switch_gs108.tscn": ["switch", ["Port1", "Port2", "Port3", "Port4", "Port5", "Port6", "Port7", "Port8"]],
	"res://scenes/network/devices/router_glinet.tscn": ["router", ["Wan", "Lan1", "Lan2"]],
	"res://scenes/network/devices/server.tscn": ["server", ["Eth0"]],
	"res://scenes/network/devices/wall_jack.tscn": ["internet", ["Jack"]],
}


## A device scene put on its own under the root.
func _device(path: String, id := "dev") -> Node:
	var device: Node = load(path).instantiate()
	device.device_id = id
	await _fresh(device)
	return device


func _test_device_ports() -> void:
	for path in DEVICES:
		var device := await _device(path)
		var want: Array = DEVICES[path][1]
		var names: Array = device.ports().map(func(z) -> String: return String(z.name))
		var label: String = path.get_file().get_basename()
		check("device %s: the script is on a StaticBody3D root" % label, device is StaticBody3D and device.get_script() == NetworkDevice)
		check("device %s: its kind is %s" % [label, DEVICES[path][0]], device.kind == DEVICES[path][0], device.kind)
		check("device %s: its ports are %s" % [label, ", ".join(want)], names == want, names)
		var ok: bool = device.ports().all(func(z) -> bool:
			return z is SnapZone and z.accepts == &"ethernet" and z.get_node_or_null("SnapPoint") != null \
				and z.get_node_or_null("CollisionShape3D") != null)
		check("device %s: every port is an ethernet SnapZone with a SnapPoint" % label, ok)
		var tag := device.get_node_or_null("Label") as Label3D
		check("device %s: its label shows its name" % label, tag != null and tag.text == device.display_name and tag.text != "")


func _test_device_port_ids() -> void:
	var router := await _device("res://scenes/network/devices/router_glinet.tscn", "router")
	check("device: a port's id is device:port in lower case", router.port_id(router.get_node("Wan")) == "router:wan"
		and router.port_id(router.get_node("Lan2")) == "router:lan2")
	check("device: a port is found by its name, any case", router.port("lan1") == router.get_node("Lan1") and router.port("WAN") == router.get_node("Wan"))
	check("device: a port it doesn't have is null", router.port("eth0") == null)
	check("device: ports have names a player can read", router.get_node("Lan1").display_name == "Router LAN 1 port", router.get_node("Lan1").display_name)
	var sw := await _device("res://scenes/network/devices/switch_gs108.tscn", "switch")
	check("device: switch ports read 'port 3'", sw.get_node("Port3").display_name == "Switch port 3", sw.get_node("Port3").display_name)
	check("device: switch port ids run port1 to port8", sw.port_id(sw.get_node("Port8")) == "switch:port8")


func _test_device_port_lights() -> void:
	var sw := await _device("res://scenes/network/devices/switch_gs108.tscn", "switch")
	var all_lit: bool = sw.ports().all(func(z) -> bool: return sw.port_light(z) != null)
	check("device: every switch port has a link light", all_lit)
	var p3: SnapZone = sw.get_node("Port3")
	var light: MeshInstance3D = sw.port_light(p3)
	check("device: lights start dark", not light.is_lit and light.shown_color() == light.off_color)
	sw.set_port_state(p3, "up")
	check("device: a port that is up is green", light.is_lit and light.shown_color() == light.on_color)
	sw.set_port_state(p3, "cut")
	check("device: a cut link is red", light.shown_color() == light.cut_color)
	sw.set_port_state(p3, "off")
	check("device: a port with no cable is dark again", not light.is_lit and not light.is_cut)
	check("device: the other ports didn't change", not sw.port_light(sw.get_node("Port4")).is_lit)


func _test_device_other_slots() -> void:
	var pc := await _device("res://scenes/network/devices/pc.tscn")
	var power := pc.get_node_or_null("Power") as SnapZone
	check("device: a PC has a power socket that isn't a network port", power != null and power.accepts == &"power" and not pc.ports().has(power))
	var mini := await _device("res://scenes/network/devices/mac_mini.tscn")
	var job := mini.get_node_or_null("Job") as SnapZone
	check("device: a Mac mini has a Job slot for work", job != null and job.accepts == &"job" and not mini.ports().has(job))
	var box := mini.get_node("Box") as MeshInstance3D
	check("device: a Mac mini is 0.2 x 0.2 x 0.036 m", (box.mesh as BoxMesh).size.is_equal_approx(Vector3(0.2, 0.036, 0.2)))
	var sw := await _device("res://scenes/network/devices/switch_gs108.tscn")
	check("device: the GS108 is 0.16 x 0.1 x 0.028 m", ((sw.get_node("Box") as MeshInstance3D).mesh as BoxMesh).size.is_equal_approx(Vector3(0.16, 0.028, 0.1)))


func _test_pc_has_a_screen() -> void:
	var pc := await _device("res://scenes/network/devices/pc.tscn")
	var screen: Node = pc.screen()
	check("device: a PC has a monitor screen", screen != null and screen.has_method("show_desktop"))
	screen.show_desktop("PC B found", PackedStringArray())
	check("device: and it can show text", screen.is_on and screen.title == "PC B found")
	var sw := await _device("res://scenes/network/devices/switch_gs108.tscn")
	check("device: a switch has no screen", sw.screen() == null)


func _test_cat6_cable() -> void:
	var cable: Node3D = Cat6Cable.instantiate()
	await _fresh(cable)
	check("cat6 cable: it is Phase 2's cable, with its two plugs", cable.has_signal("plugged") and cable.get_node("EndA") is GrabbablePart and cable.get_node("EndB") is GrabbablePart)
	var plug := (cable.get_node("EndA/Mesh") as MeshInstance3D).mesh as BoxMesh
	check("cat6 cable: its plugs are small enough for switch ports side by side", plug.size.x < 0.018, plug.size)


# --- Step 4: network missions and their goals --------------------------------

## A network mission on its own (no scene), with this goal and graph, to
## check its goal logic without loading a scene.
func _goal_mission(goal: Dictionary, g: NetworkGraphScript) -> Node:
	var m: Node = NetworkMission.new()
	m.config = {"goal": goal}
	m.graph = g
	return m


func _test_goal_connected() -> void:
	var g := _graph({"pc_a": "pc", "pc_b": "pc"})
	var m := _goal_mission({"connected": ["pc_a", "pc_b"]}, g)
	check("goal connected: not met with no cable", not m.goal_met())
	m.note_plugged("pc_a:eth0", "pc_b:eth0")
	check("goal connected: met once a cable joins them", m.goal_met())
	m.note_unplugged("pc_b:eth0", "pc_a:eth0")
	check("goal connected: not met once it is pulled out", not m.goal_met())
	m.free()


func _test_goal_reach() -> void:
	var g := _star()
	g.add_device("router", "router")
	g.add_device("internet", "internet")
	var m := _goal_mission({"reach": "internet", "from": ["pc_a", "pc_b", "pc_c"]}, g)
	m.note_plugged("sw:port8", "router:lan1")
	check("goal reach: not met without the WAN cable", not m.goal_met())
	m.note_plugged("router:lan2", "internet:jack")
	check("goal reach: not met through a LAN port", not m.goal_met())
	m.note_unplugged("router:lan2", "internet:jack")
	m.note_plugged("router:wan", "internet:jack")
	check("goal reach: met with WAN to the jack", m.goal_met())
	m.note_unplugged("pc_b:eth0", "sw:port2")
	check("goal reach: not met when one PC is cut off", not m.goal_met())
	m.free()


func _test_goal_delivered() -> void:
	var m := _goal_mission({"delivered": {"from": "pc_a", "to": "pc_c", "packets": 4}}, _star())
	check("goal delivered: not met before anything arrives", not m.goal_met())
	m.note_delivered("pc_a", "pc_b", 4)
	check("goal delivered: not met by a message to someone else", not m.goal_met())
	m.note_delivered("pc_a", "pc_c", 2)
	check("goal delivered: not met by a shorter message", not m.goal_met())
	m.note_delivered("pc_a", "pc_c", 4)
	check("goal delivered: met by the whole message", m.goal_met())
	m.free()


func _test_goal_cut_then_restore() -> void:
	var g := _graph({"pc_a": "pc", "switch": "switch", "server": "server"})
	var m := _goal_mission({"cut_then_restore": ["switch:port3", "server:eth0"]}, g)
	m.note_plugged("pc_a:eth0", "switch:port1")
	m.note_plugged("switch:port3", "server:eth0")
	m.note_packet_arrived("pc_a", "server")
	check("goal cut_then_restore: packets alone don't meet it", not m.goal_met())
	m.note_unplugged("pc_a:eth0", "switch:port1")
	check("goal cut_then_restore: pulling another cable isn't the cut", not m.was_cut)
	m.note_plugged("pc_a:eth0", "switch:port1")
	m.note_unplugged("server:eth0", "switch:port3")
	check("goal cut_then_restore: pulling the marked cable is", m.was_cut and not m.restored)
	m.note_packet_arrived("pc_a", "server")
	check("goal cut_then_restore: not met while it's out", not m.goal_met())
	m.note_plugged("switch:port5", "server:eth0")
	check("goal cut_then_restore: back in (another port is fine) is restored", m.restored)
	check("goal cut_then_restore: not met until packets get through again", not m.goal_met())
	m.note_packet_arrived("pc_a", "server")
	check("goal cut_then_restore: met once they do", m.goal_met())
	m.free()


func _test_goal_survives_any_single_cut() -> void:
	var ids := ["pc_a", "pc_b", "pc_c", "pc_d"]
	var g := _graph({"pc_a": "pc", "pc_b": "pc", "pc_c": "pc", "pc_d": "pc", "sw1": "switch", "sw2": "switch"})
	g.connect_ports("pc_a:eth0", "sw1:port1")
	g.connect_ports("pc_b:eth0", "sw1:port2")
	g.connect_ports("pc_c:eth0", "sw2:port1")
	g.connect_ports("pc_d:eth0", "sw2:port2")
	var m := _goal_mission({"survives_any_single_cut": ids}, g)
	check("goal redundancy: not met while the switches aren't joined", not m.goal_met())
	m.note_plugged("sw1:port8", "sw2:port8")
	check("goal redundancy: one cable between the switches is a single point of failure", not m.goal_met())
	m.note_plugged("sw1:port7", "sw2:port7")
	check("goal redundancy: a second cable between them meets it", m.goal_met())
	check("goal redundancy: a PC's only cable isn't counted as a cut to survive", g.is_own_cable(g.links[0]) and not g.is_own_cable(g.links[4]))
	m.free()


func _test_goal_jobs_done() -> void:
	var m := _goal_mission({"jobs_done": 12, "min_machines": 3}, _star())
	m.job_counts = {"mini_a": 6, "mini_b": 6}
	check("goal jobs: 12 jobs on 2 machines isn't enough machines", not m.goal_met())
	m.job_counts = {"mini_a": 4, "mini_b": 4, "mini_c": 3}
	check("goal jobs: 11 jobs isn't all of them", not m.goal_met())
	m.job_counts = {"mini_a": 4, "mini_b": 4, "mini_c": 4, "mini_d": 0}
	check("goal jobs: 12 jobs on 3 machines meets it", m.goal_met())
	m.free()


func _test_registry_checks_goals() -> void:
	var bad := {
		"no kind": {"what": 1},
		"two kinds": {"connected": ["a", "b"], "reach": "internet", "from": ["a"]},
		"one device": {"connected": ["a"]},
		"reach without from": {"reach": "internet"},
		"no packet count": {"delivered": {"from": "a", "to": "b"}},
		"a device, not a port": {"cut_then_restore": ["switch", "server:eth0"]},
		"jobs as text": {"jobs_done": "twelve"},
	}
	for label in bad:
		var r = _registry_with({"goal": bad[label]})
		check("registry: a goal with %s is an error" % label, r.errors.size() == 1 and r.errors[0].contains(".goal"), r.errors)
	for goal in [{"connected": ["a", "b"]}, {"reach": "internet", "from": ["a"]},
			{"delivered": {"from": "a", "to": "b", "packets": 4}}, {"cut_then_restore": ["s:port3", "srv:eth0"]},
			{"survives_any_single_cut": ["a", "b"]}, {"jobs_done": 12, "min_machines": 3}]:
		var r = _registry_with({"goal": goal})
		check("registry: goal %s reads cleanly" % goal.keys()[0], r.errors.is_empty(), r.errors)


## A registry with one small mission, plus `extra` fields on the mission.
func _registry_with(extra: Dictionary, slots := {}) -> Object:
	var m := {"id": "m", "title": "T", "scene": "res://scenes/setup_pc/go_online.tscn", "intro": ["a"], "success": ["b"],
		"scoring": {"full": 100, "per_mistake": 10},
		"parts": {"C/EndA": {"type": "ethernet", "name": "plug"}},
		"slots": slots if not slots.is_empty() else {"P1": {"accepts": "ethernet", "name": "port", "hint": "h"}}}
	m.merge(extra, true)
	var r = ModuleRegistry.new()
	r.read({"modules": [{"id": "net", "title": "Net", "missions": [m]}]})
	return r


func _test_registry_optional_slots() -> void:
	var slots := {}
	for i in 8:
		slots["Switch/Port%d" % (i + 1)] = {"accepts": "ethernet", "name": "port", "hint": "h", "optional": true}
	var r = _registry_with({}, slots)
	check("registry: 8 optional ports with 1 plug is fine (they needn't all be filled)", r.errors.is_empty(), r.errors)
	slots["Switch/Port1"].optional = "yes"
	r = _registry_with({}, slots)
	check("registry: optional must be true or false", r.errors.size() == 1 and r.errors[0].contains("optional"), r.errors)


## Loads Connect to the network (Phase 2) with this registry change to its
## slots, and returns the mission.
func _go_online_with(slot_changes: Dictionary) -> Node3D:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules.json"))
	for module in data.modules:
		for m in module.missions:
			if m.id == "go_online":
				for path in slot_changes:
					m.slots[path].merge(slot_changes[path], true)
	var r = ModuleRegistry.new()
	r.read(data)
	manager.use_registry(r)
	return await _fresh(GoOnline.instantiate())


func _test_optional_slot_is_not_needed() -> void:
	var mission := await _go_online_with({"Router/Lan1": {"optional": true}})
	check("mission: an optional slot isn't on the list of slots to fill", mission.goals.size() == 1 and mission.zones.size() == 2, mission.goals.size())
	mission.get_node("Room/MouseGrabber").part_grabbed.emit(null)
	var plug: GrabbablePart = mission.get_node("EthernetCable/EndA")
	await _carry_and_drop(plug, mission.get_node("Tower/Ethernet/CollisionShape3D").global_position)
	check("mission: so it finishes once the other slot is filled", manager.state == manager.State.SUCCESS, manager.state)


func _test_old_mission_finishes_the_old_way() -> void:
	var mission := await _go_online_with({})
	check("old mission: no goal, both slots to fill", not mission.config.has("goal") and mission.goals.size() == 2)
	mission.get_node("Room/MouseGrabber").part_grabbed.emit(null)
	await _carry_and_drop(mission.get_node("EthernetCable/EndA"), mission.get_node("Tower/Ethernet/CollisionShape3D").global_position)
	check("old mission: one slot filled isn't done", manager.state == manager.State.ACTIVE)
	await _carry_and_drop(mission.get_node("EthernetCable/EndB"), mission.get_node("Router/Lan1/CollisionShape3D").global_position)
	check("old mission: both filled finishes it", manager.state == manager.State.SUCCESS)


func _test_goal_mission_ignores_full_slots() -> void:
	# The same mission with a goal: its slots being full no longer ends it.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules.json"))
	for module in data.modules:
		for m in module.missions:
			if m.id == "go_online":
				m.goal = {"connected": ["pc_a", "pc_b"]}
	var r = ModuleRegistry.new()
	r.read(data)
	manager.use_registry(r)
	var mission: Node3D = await _fresh(GoOnline.instantiate())
	mission.get_node("Room/MouseGrabber").part_grabbed.emit(null)
	await _carry_and_drop(mission.get_node("EthernetCable/EndA"), mission.get_node("Tower/Ethernet/CollisionShape3D").global_position)
	await _carry_and_drop(mission.get_node("EthernetCable/EndB"), mission.get_node("Router/Lan1/CollisionShape3D").global_position)
	check("goal mission: full slots don't finish a mission with a goal", manager.state == manager.State.ACTIVE, manager.state)


func _test_cable_start_ports() -> void:
	var bench := Node3D.new()
	bench.name = "Bench"
	var cable := Cable.instantiate()
	cable.end_a_position = Vector3(-0.2, 0.0, 0.0)
	cable.end_b_position = Vector3(0.2, 0.0, 0.0)
	cable.start_ports = [NodePath("../Port1"), NodePath("../Port2")] as Array[NodePath]
	bench.add_child(cable)
	await _fresh(bench)
	for end_name in ["EndA", "EndB"]:
		(cable.get_node(end_name) as GrabbablePart).part_type = &"ethernet"
	var p1 := _port(bench, "Port1", "ethernet", Vector3(-0.1, 0.0, -0.3))
	var p2 := _port(bench, "Port2", "ethernet", Vector3(0.1, 0.0, -0.3))
	var events := []
	cable.plugged.connect(func(_c, x, y) -> void: events.append([x, y]))
	await _settle()
	cable.plug_in_start_ports()
	check("start ports: a cable can start plugged in", cable.is_plugged() and p1.installed_part == cable.get_node("EndA") and p2.installed_part == cable.get_node("EndB"))
	check("start ports: and says so, like a player plugging it", events == [[p1, p2]], events)
	var a: GrabbablePart = cable.get_node("EndA")
	a.grab()
	a.drop()
	check("start ports: pulled out and let go, a plug goes to where it started on the table", not a.is_installed and a.global_position.is_equal_approx(Vector3(-0.2, 0, 0)), a.global_position)


# --- Step 5: missions 1-3 -----------------------------------------------------

const MISSIONS_1_3 := {
	"build_network.connect_two": "res://scenes/network/connect_two.tscn",
	"build_network.switch": "res://scenes/network/switch.tscn",
	"build_network.router": "res://scenes/network/router.tscn",
}


## Loads a network mission scene and returns it.
func _mission(path: String) -> Node3D:
	return await _fresh(load(path).instantiate())


## The middle of a slot's drop area: where a carried part has to be for the
## slot to see it.
func _over(mission: Node3D, slot_path: String) -> Vector3:
	return (mission.get_node(slot_path).get_node("CollisionShape3D") as Node3D).global_position


## The real input path, as the mouse does it: press on the part through the
## camera, carry it above the table to over `to`, let go.
func _drag(mission: Node3D, part_path: String, to: Vector3) -> void:
	var part: GrabbablePart = mission.get_node(part_path)
	var grabber = mission.get_node("Room/MouseGrabber")
	var camera: Camera3D = mission.get_node("Room/Camera3D")
	var middle: Vector3 = (part.get_node("CollisionShape3D") as Node3D).global_position
	if grabber.try_grab_at(camera.unproject_position(middle)) != part:
		check("pressing on %s through the camera picks it up" % part_path, false)
		return
	grabber.carry_to(camera.unproject_position(Vector3(to.x, grabber.carry_height, to.z)))
	await _settle()
	grabber.release()
	await _settle()


## Drags a plug into a slot.
func _plug(mission: Node3D, part_path: String, slot_path: String) -> void:
	await _drag(mission, part_path, _over(mission, slot_path))


func _test_build_network_is_in_the_registry() -> void:
	var r = ModuleRegistry.load_from()
	check("registry: data/modules.json still loads cleanly", r.errors.is_empty(), r.errors)
	var module: Dictionary = {}
	for m in r.modules:
		if m.id == "build_network":
			module = m
	check("registry: there is a Build a Network module in Computer", module.get("title") == "Build a Network" and module.get("category") == "computer", module)
	for id in MISSIONS_1_3:
		var m: Dictionary = r.mission(id)
		check("registry: %s has its scene, a goal and the usual scoring" % id, m.get("scene") == MISSIONS_1_3[id]
			and m.has("goal") and m.scoring.full == 100 and m.scoring.per_mistake == 10 and m.difficulty == "Beginner", m.get("scene"))


func _test_network_scenes_load() -> void:
	for id in MISSIONS_1_3:
		var mission := await _mission(MISSIONS_1_3[id])
		check("%s: the scene loads with no problems" % id, mission.problems.is_empty(), mission.problems)
		check("%s: every port is an optional slot" % id, mission.goals.is_empty() and mission.zones.size() > 0)
		check("%s: it starts in Intro, not finished" % id, manager.state == manager.State.INTRO and not mission.finished)


func _test_connect_two() -> void:
	var mission := await _mission(MISSIONS_1_3["build_network.connect_two"])
	var screen: Node = mission.devices.pc_a.screen()
	check("connect two: PC A's screen starts not connected", screen.is_on and "not connected" in "\n".join(screen.lines), screen.lines)
	await _plug(mission, "Cable/EndA", "PcA/Eth0")
	check("connect two: one end in doesn't finish it", manager.state == manager.State.ACTIVE and mission.graph.links.is_empty())
	await _plug(mission, "Cable/EndB", "PcB/Eth0")
	check("connect two: both ends in joins the PCs", mission.graph.path("pc_a", "pc_b") == ["pc_a", "pc_b"])
	check("connect two: and finishes the mission", manager.state == manager.State.SUCCESS and manager.score == 100, manager.state)
	var light_a: MeshInstance3D = mission.devices.pc_a.port_light(mission.get_node("PcA/Eth0"))
	var light_b: MeshInstance3D = mission.devices.pc_b.port_light(mission.get_node("PcB/Eth0"))
	check("connect two: both link lights are green", light_a.is_lit and light_b.is_lit and light_a.shown_color() == light_a.on_color)
	check("connect two: PC A's screen says PC B found", screen.lines.has("PC B found"), screen.lines)


func _test_connect_two_power_socket_is_a_mistake() -> void:
	var mission := await _mission(MISSIONS_1_3["build_network.connect_two"])
	await _plug(mission, "Cable/EndA", "PcA/Power")
	check("connect two: Ethernet into the power socket is turned away", not mission.get_node("Cable/EndA").is_installed)
	check("connect two: and is a mistake", manager.mistakes == 1, manager.mistakes)
	check("connect two: the panel says where it goes", "\n".join(mission.panel.lines).contains("LAN port"), mission.panel.lines)


func _test_unplugging_in_a_mission() -> void:
	var mission := await _mission(MISSIONS_1_3["build_network.switch"])
	await _plug(mission, "CableA/EndA", "PcA/Eth0")
	await _plug(mission, "CableA/EndB", "Switch/Port4")
	var light: MeshInstance3D = mission.devices.switch.port_light(mission.get_node("Switch/Port4"))
	check("unplug: the switch port is lit once PC A is cabled to it", light.is_lit and mission.graph.links.size() == 1)
	await _drag(mission, "CableA/EndB", Vector3(0.3, 0.9, 0.3))
	check("unplug: pulling the plug out takes the link away", mission.graph.links.is_empty() and not mission.get_node("CableA/EndB").is_installed)
	check("unplug: the port's light goes dark", not light.is_lit)
	check("unplug: and it isn't a mistake", manager.mistakes == 0, manager.mistakes)
	check("unplug: PC A's screen is not connected again", "not connected" in "\n".join(mission.devices.pc_a.screen().lines))


func _test_switch_any_ports() -> void:
	var mission := await _mission(MISSIONS_1_3["build_network.switch"])
	var plan := [["CableA", "PcA/Eth0", "Switch/Port2"], ["CableB", "PcB/Eth0", "Switch/Port5"], ["CableC", "PcC/Eth0", "Switch/Port8"]]
	for i in plan.size():
		await _plug(mission, plan[i][0] + "/EndA", plan[i][1])
		await _plug(mission, plan[i][0] + "/EndB", plan[i][2])
		if i == 1:
			check("switch: two PCs on the switch isn't all three", manager.state == manager.State.ACTIVE and mission.graph.path("pc_a", "pc_b").size() == 3)
	check("switch: any three ports join all three PCs", mission.graph.all_connected(["pc_a", "pc_b", "pc_c"]))
	check("switch: and that finishes it", manager.state == manager.State.SUCCESS and manager.score == 100, manager.state)
	check("switch: PC B finds the other two", mission.devices.pc_b.screen().lines.has("PC A, PC C found"), mission.devices.pc_b.screen().lines)
	check("switch: the panel ticks the goal", "\n".join(mission.panel.lines).contains("Mission complete") or mission.panel.title == "Mission complete!", mission.panel.title)


func _test_router_starts_cabled() -> void:
	var mission := await _mission(MISSIONS_1_3["build_network.router"])
	check("router: the PCs start cabled to the switch", mission.graph.links.size() == 3 and mission.graph.all_connected(["pc_a", "pc_b", "pc_c"]))
	check("router: their switch ports start lit", mission.devices.switch.port_light(mission.get_node("Switch/Port1")).is_lit)
	check("router: but nobody reaches the internet", mission.graph.path("pc_a", "internet").is_empty())
	check("router: and starting cabled is no mistake and doesn't start the clock", manager.mistakes == 0 and manager.state == manager.State.INTRO)


func _test_router_wan_lan_swapped() -> void:
	var mission := await _mission(MISSIONS_1_3["build_network.router"])
	await _plug(mission, "InternetCable/EndA", "Router/Lan1")
	check("router: the internet cable into a LAN port is turned away", not mission.get_node("InternetCable/EndA").is_installed and manager.mistakes == 1, manager.mistakes)
	check("router: with LAN's hint", "\n".join(mission.panel.lines).contains("LAN is your side"), mission.panel.lines)
	await _plug(mission, "Uplink/EndA", "Router/Wan")
	check("router: the switch's cable into WAN is turned away too", not mission.get_node("Uplink/EndA").is_installed and manager.mistakes == 2, manager.mistakes)
	check("router: with WAN's hint", "\n".join(mission.panel.lines).contains("WAN goes out to the internet"), mission.panel.lines)
	await _plug(mission, "InternetCable/EndA", "Switch/Port6")
	check("router: and the internet cable into the switch", manager.mistakes == 3, manager.mistakes)


func _test_router_perfect_run() -> void:
	var mission := await _mission(MISSIONS_1_3["build_network.router"])
	await _plug(mission, "Uplink/EndA", "Switch/Port8")
	await _plug(mission, "Uplink/EndB", "Router/Lan1")
	check("router: switch to LAN isn't online yet", manager.state == manager.State.ACTIVE)
	await _plug(mission, "InternetCable/EndA", "Jack/Jack")
	await _plug(mission, "InternetCable/EndB", "Router/Wan")
	check("router: every PC reaches the internet", ["pc_a", "pc_b", "pc_c"].all(func(id) -> bool: return mission.graph.path(id, "internet").size() == 4))
	check("router: and the mission is done, with no mistakes", manager.state == manager.State.SUCCESS and manager.score == 100, manager.score)
	check("router: the PCs' screens say they're online", mission.devices.pc_c.screen().lines.has("Internet: online"), mission.devices.pc_c.screen().lines)
