class_name NetworkGraph extends RefCounted
## The network a player builds, as data: devices, the cables between their
## ports, and whether each cable's link is up. Pure logic with no scene code,
## so it can be checked headless (tests/run_network_tests.gd).
##
## Ports are written "device:port", e.g. "pc_a:eth0" or "router:wan". A cable
## joins two ports, and a port holds one cable at most.
##
## How data moves, as on real networks:
## - A PC or a server only sends and receives. Data never passes *through* it,
##   even when it has two cables; only a switch or a router forwards.
## - The router's WAN port is the only way to the internet.
##
## The mission scripts (scripts/missions/network_mission.gd) keep one of these
## and check their goal against it after every change.

## The kinds of device a network can have.
const KINDS := ["pc", "switch", "router", "server", "internet"]
## Devices that pass data on from one cable to another.
const FORWARDS := ["switch", "router"]

## Device id -> kind.
var devices: Dictionary = {}
## Every cable as {a, b, up}, a and b "device:port".
var links: Array = []


func add_device(id: String, kind: String) -> void:
	if not kind in KINDS:
		push_error("NetworkGraph: %s isn't a kind of device (%s)" % [kind, ", ".join(KINDS)])
		return
	devices[id] = kind


## Joins two ports with a cable. Does nothing (and says why) if either port
## already has a cable, or names a device the network doesn't have.
func connect_ports(a: String, b: String) -> bool:
	for port in [a, b]:
		if not devices.has(device_of(port)):
			push_error("NetworkGraph: no device %s (port %s)" % [device_of(port), port])
			return false
		if port_in_use(port):
			return false
	if a == b:
		return false
	links.append({"a": a, "b": b, "up": true})
	return true


func disconnect_ports(a: String, b: String) -> void:
	var at := _find(a, b)
	if at != -1:
		links.remove_at(at)


## Marks a cable's link up or down without unplugging it (a cut, then a fix).
func set_link_up(a: String, b: String, up: bool) -> void:
	var at := _find(a, b)
	if at != -1:
		links[at].up = up


func is_link_up(a: String, b: String) -> bool:
	var at := _find(a, b)
	return at != -1 and links[at].up


func port_in_use(port: String) -> bool:
	return links.any(func(l) -> bool: return l.a == port or l.b == port)


## The device ids data passes through from one device to another, both ends
## included, by the fewest hops. [] when there is no way.
func path(from_id: String, to_id: String) -> Array[String]:
	var out: Array[String] = []
	if not devices.has(from_id) or not devices.has(to_id):
		return out
	if from_id == to_id:
		out.append(from_id)
		return out
	var came_from := {from_id: ""}
	var queue: Array[String] = [from_id]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		# Only the sender and forwarding devices pass data on.
		if at != from_id and not devices[at] in FORWARDS:
			continue
		for next in _neighbours(at):
			if came_from.has(next):
				continue
			came_from[next] = at
			if next == to_id:
				var step := to_id
				while step != "":
					out.push_front(step)
					step = came_from[step]
				return out
			queue.append(next)
	return out


## Every other device data from `from_id` can reach.
func reachable(from_id: String) -> Array[String]:
	var out: Array[String] = []
	for id in devices:
		if id != from_id and not path(from_id, id).is_empty():
			out.append(id)
	return out


## True when every device in `ids` can reach every other.
func all_connected(ids: Array) -> bool:
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if path(ids[i], ids[j]).is_empty():
				return false
	return true


## The links whose cut leaves some device unable to reach one it could reach
## before, as [a, b] port pairs. A network with none of these has no single
## point of failure in its cables.
func bridges() -> Array:
	var before := _reach_table()
	var out := []
	for link in links:
		if not link.up:
			continue
		link.up = false
		if _reach_table() != before:
			out.append([link.a, link.b])
		link.up = true
	return out


## Cuts each working link in turn and checks `ids` are still all connected.
## True only if no one cut splits them, and they are connected to start with.
func survives_any_single_cut(ids: Array) -> bool:
	return cut_results(ids).all(func(r) -> bool: return r.ok) and all_connected(ids)


## What happens to `ids` when each working link is cut in turn:
## [{a, b, ok}], ok meaning they all still reach each other. The redundancy
## mission shows these one by one.
func cut_results(ids: Array) -> Array:
	var out := []
	for link in links:
		if not link.up:
			continue
		link.up = false
		out.append({"a": link.a, "b": link.b, "ok": all_connected(ids)})
		link.up = true
	return out


static func device_of(port: String) -> String:
	return port.get_slice(":", 0)


static func port_name(port: String) -> String:
	return port.get_slice(":", 1) if port.contains(":") else ""


## Devices one working cable away from `id` that data can go to. A cable to
## the internet only counts from a router's WAN port.
func _neighbours(id: String) -> Array[String]:
	var out: Array[String] = []
	for link in links:
		if not link.up:
			continue
		var mine := ""
		var theirs := ""
		if device_of(link.a) == id:
			mine = link.a
			theirs = link.b
		elif device_of(link.b) == id:
			mine = link.b
			theirs = link.a
		else:
			continue
		if not _internet_ok(mine, theirs):
			continue
		var other := device_of(theirs)
		if not out.has(other):
			out.append(other)
	return out


## A cable that touches the internet works only if its other end is a
## router's WAN port.
func _internet_ok(a: String, b: String) -> bool:
	for pair in [[a, b], [b, a]]:
		if devices.get(device_of(pair[0])) == "internet":
			var other: String = pair[1]
			return devices.get(device_of(other)) == "router" and port_name(other) == "wan"
	return true


## Which devices each device reaches, to compare before and after a cut.
func _reach_table() -> Dictionary:
	var table := {}
	for id in devices:
		var r := reachable(id)
		r.sort()
		table[id] = r
	return table


func _find(a: String, b: String) -> int:
	for i in links.size():
		var l: Dictionary = links[i]
		if (l.a == a and l.b == b) or (l.a == b and l.b == a):
			return i
	return -1
