extends StaticBody3D
## A device on the network the player builds: a PC, a Mac mini, a switch, a
## router, a server or the wall's Internet jack. It goes on the root of each
## scene in scenes/network/devices/.
##
## Its ports are SnapZone children named after the port: Eth0, Eth1, Lan1,
## Lan2, Wan, Port1 to Port8, Jack. In the network (scripts/network/
## network_graph.gd) a port is "device_id:port", the port's name in lower
## case, e.g. "pc_a:eth0" or "router:wan". Each port has a small link light
## (a child named Light, scripts/parts/link_light.gd) that the network
## mission turns green when a cable joins the port to another, off when it is
## pulled out, and red when the mission marks the link as cut.
##
## Other SnapZone children (a PC's Power socket, a Mac mini's Job slot) are
## not network ports. The mission's registry entry still lists them.

const SnapZone := preload("res://scripts/snap_zone.gd")

## The port names a device can have (any other SnapZone isn't a network port).
const PORT_PATTERN := "^(Eth[0-9]|Lan[0-9]|Wan|Port[0-9]+|Jack)$"

## The device's id in the network and in the mission's goal, e.g. "pc_a".
@export var device_id := ""
## What it is: one of NetworkGraph.KINDS (pc, switch, router, server, internet).
@export var kind := "pc"
## What the player reads on its label and screen, e.g. "PC A".
@export var display_name := ""

var _pattern := RegEx.create_from_string(PORT_PATTERN)


func _ready() -> void:
	var tag := get_node_or_null("Label") as Label3D
	if tag and display_name != "":
		tag.text = display_name
	for zone in ports():
		var label := port_label(zone)
		zone.display_name = "%s %s%s" % [display_name, label, "" if label.begins_with("port") else " port"]
		set_port_state(zone, "off")


## The device's network ports, in scene order.
func ports() -> Array[SnapZone]:
	var out: Array[SnapZone] = []
	for child in get_children():
		if child is SnapZone and _pattern.search(child.name) != null:
			out.append(child)
	return out


## The port's id in the network, e.g. "pc_a:eth0".
func port_id(zone: Node) -> String:
	return "%s:%s" % [device_id, String(zone.name).to_lower()]


## The port named `port_name` ("eth0", "wan"...; any case), or null.
func port(port_name: String) -> SnapZone:
	for zone in ports():
		if String(zone.name).to_lower() == port_name.to_lower():
			return zone
	return null


## How a port is written for the player: "Eth0" -> "Ethernet", "Lan1" ->
## "LAN 1", "Wan" -> "WAN", "Port3" -> "port 3", "Jack" -> "Internet".
static func port_label(zone: Node) -> String:
	var n := String(zone.name)
	if n == "Eth0":
		return "Ethernet"
	if n.begins_with("Eth"):
		return "Ethernet " + n.substr(3)
	if n.begins_with("Lan"):
		return "LAN " + n.substr(3)
	if n == "Wan":
		return "WAN"
	if n.begins_with("Port"):
		return "port " + n.substr(4)
	if n == "Jack":
		return "Internet"
	return n


## Shows a port's link: "up" (green), "off" (dark) or "cut" (red).
func set_port_state(zone: Node, state: String) -> void:
	var light := zone.get_node_or_null("Light")
	if light == null:
		return
	light.set_lit(state == "up")
	light.set_cut(state == "cut")


## The light on a port (null if it has none).
func port_light(zone: Node) -> MeshInstance3D:
	return zone.get_node_or_null("Light") as MeshInstance3D


## The device's screen (a PC's monitor), or null.
func screen() -> Node:
	return find_child("MonitorScreen", true, false)
