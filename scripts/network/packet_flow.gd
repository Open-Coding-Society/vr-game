extends Node3D
## Packets you can see: a message split into numbered packets that travel
## along the cables, hop by hop, and are put back in order at the far end.
##
## A network mission (scripts/missions/network_mission.gd) has one of these as
## a child named PacketFlow and calls setup() with itself. Each packet takes
## the network's path() and moves from port to port along the cable at
## `speed`, pausing at each switch or router. Each one also waits a small
## random time before it leaves, so they can arrive out of order.
##
## If a link on a packet's way goes down (a cable is pulled out), the packet
## stops at the last device it reached and waits; the sender's screen says
## "Connection lost". As soon as there is a way again, it carries on.
##
## Kept cheap for the Quest: packets are plain Node3Ds moved in step(), with
## no physics, and no more than `max_packets` are on the cables at once; the
## rest wait their turn at the sender.

const NetworkGraph := preload("res://scripts/network/network_graph.gd")
const PacketScene := preload("res://scenes/network/packet.tscn")

## One packet reached the device it was sent to. `index` counts from 1.
signal packet_arrived(from_id: String, to_id: String, index: int)
## Every packet of a message arrived, and it was put back together.
signal message_delivered(from_id: String, to_id: String, packets: int, text: String)

## How fast a packet moves along a cable (meters per second).
@export var speed := 0.3
## How long a packet stops at a switch or a router (seconds).
@export var pause_s := 0.4
## Each packet waits up to this long before it leaves (seconds), so packets
## can arrive out of order.
@export var delay_spread := 0.8
## A stream sends one packet this often (seconds).
@export var stream_every_s := 0.7
## The most packets on the cables at once.
@export var max_packets := 20
## How high above a port a packet travels (meters).
@export var lift := 0.03

## Set by setup(): the mission whose network the packets use.
var mission: Node = null
## Packets on their way: [{node, from, to, index, count, message, at, path,
## hop, link, dist, wait, stuck}]
var live: Array = []
## Packets waiting at their sender for room on the cables (max_packets).
var queued: Array = []
## Messages being sent: [{from, to, count, text, arrived}]
var messages: Array = []
## Streams: [{from, to, next_index, timer}]
var streams: Array = []
## The most packets ever on the cables at once (tests check the cap).
var peak := 0
## Delays (seconds) to use, in order, before random ones (tests set them).
var next_delays: Array = []

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## Called by the mission once its network is built.
func setup(owner_mission: Node) -> void:
	mission = owner_mission


## Splits a message from one device to another into `count` packets and
## sends them. The receiver's screen shows them put back in order.
func send(from_id: String, to_id: String, count: int, text: String) -> void:
	var message := {"from": from_id, "to": to_id, "count": count, "text": text, "arrived": []}
	messages.append(message)
	for i in count:
		_queue({"from": from_id, "to": to_id, "index": i + 1, "count": count, "message": message})
	_show_sender(from_id)


## Sends packets from one device to another, one every stream_every_s,
## until stop_streams().
func stream(from_id: String, to_id: String) -> void:
	streams.append({"from": from_id, "to": to_id, "next_index": 1, "timer": 0.0, "arrived": 0})


func stop_streams() -> void:
	streams.clear()


## Every packet that has arrived from one device to another so far.
func arrived_count(from_id: String, to_id: String) -> int:
	var n := 0
	for m in messages:
		if m.from == from_id and m.to == to_id:
			n += m.arrived.size()
	for s in streams:
		if s.from == from_id and s.to == to_id:
			n += s.arrived
	return n


## True when some packet from `from_id` is stopped by a broken link.
func is_lost(from_id: String) -> bool:
	return live.any(func(p) -> bool: return p.from == from_id and p.stuck)


func _process(delta: float) -> void:
	step(delta)


## Moves everything on by `delta` seconds. _process calls it every frame;
## tests call it themselves with set_process(false).
func step(delta: float) -> void:
	if mission == null:
		return
	for s in streams:
		s.timer -= delta
		if s.timer <= 0.0 and live.size() + queued.size() < max_packets:
			s.timer = stream_every_s
			_queue({"from": s.from, "to": s.to, "index": s.next_index, "count": 0, "message": {}, "stream": s})
			s.next_index += 1
	while not queued.is_empty() and live.size() < max_packets:
		_launch(queued.pop_front())
	var lost_before := {}
	for p in live:
		lost_before[p.from] = lost_before.get(p.from, false) or p.stuck
	for p in live.duplicate():
		_move(p, delta)
	var senders := {}
	for p in live:
		senders[p.from] = true
	for id in lost_before:
		senders[id] = true
	for id in senders:
		if lost_before.get(id, false) != is_lost(id):
			_show_sender(id)


func _queue(packet: Dictionary) -> void:
	if live.size() < max_packets:
		_launch(packet)
	else:
		queued.append(packet)


func _launch(packet: Dictionary) -> void:
	var node: Node3D = PacketScene.instantiate()
	add_child(node)
	var tag := node.get_node_or_null("Label") as Label3D
	if tag:
		tag.text = "%d/%d" % [packet.index, packet.count] if packet.count > 0 else str(packet.index)
	packet.node = node
	packet.at = packet.from
	packet.path = []
	packet.hop = 0
	packet.link = {}
	packet.dist = 0.0
	packet.stuck = false
	packet.wait = next_delays.pop_front() if not next_delays.is_empty() else _rng.randf_range(0.0, delay_spread)
	node.global_position = _device_position(packet.from)
	live.append(packet)
	peak = maxi(peak, live.size())


func _move(p: Dictionary, delta: float) -> void:
	if p.wait > 0.0:
		p.wait -= delta
		return
	var graph: NetworkGraph = mission.graph
	if p.at == p.to:
		_arrive(p)
		return
	if p.path.is_empty():
		p.path = graph.path(p.at, p.to)
		p.hop = 0
		if p.path.is_empty():
			p.stuck = true
			return
	var link := graph.link_between(p.path[p.hop], p.path[p.hop + 1])
	if link.is_empty():
		# The cable on this hop is gone: back to the last device, and wait for
		# a way on (the same cable plugged back in, or another path).
		p.stuck = true
		p.path = []
		p.link = {}
		p.dist = 0.0
		p.node.global_position = _device_position(p.at)
		return
	p.stuck = false
	if link != p.link:
		p.link = link
		p.dist = 0.0
	var from := _port_position(link.a)
	var to := _port_position(link.b)
	var length := maxf(from.distance_to(to), 0.001)
	p.dist += speed * delta
	if p.dist < length:
		p.node.global_position = from.lerp(to, p.dist / length)
		return
	# Reached the next device.
	p.node.global_position = to
	p.hop += 1
	p.at = p.path[p.hop]
	p.link = {}
	p.dist = 0.0
	if p.at == p.to:
		_arrive(p)
	elif graph.devices.get(p.at) in NetworkGraph.FORWARDS:
		p.wait = pause_s


func _arrive(p: Dictionary) -> void:
	live.erase(p)
	remove_child(p.node)
	p.node.queue_free()
	if p.has("stream"):
		p.stream.arrived += 1
	else:
		p.message.arrived.append(p.index)
	packet_arrived.emit(p.from, p.to, p.index)
	if p.has("stream"):
		_show_sender(p.from)
		return
	_show_receiver(p.message)
	if p.message.arrived.size() == p.message.count:
		_show_sender(p.from)
		message_delivered.emit(p.from, p.to, p.message.count, p.message.text)


## The sender's screen: how the sending is going, or "Connection lost".
func _show_sender(id: String) -> void:
	var screen := _screen(id)
	if screen == null:
		return
	var lines := PackedStringArray()
	if is_lost(id):
		lines.append("Connection lost")
		lines.append("Waiting for a way through...")
	else:
		for m in messages:
			if m.from == id:
				lines.append("To %s: %d of %d packets arrived" % [_name(m.to), m.arrived.size(), m.count])
		for s in streams:
			if s.from == id:
				lines.append("Sending to %s" % _name(s.to))
				lines.append("Packets arrived: %d" % s.arrived)
	screen.show_desktop(_name(id), lines)


## The receiver's screen: the packets as they came, then in order, then the
## message itself once every packet is there.
func _show_receiver(message: Dictionary) -> void:
	var screen := _screen(message.to)
	if screen == null:
		return
	var arrived: Array = message.arrived
	var in_order := PackedStringArray()
	for i in range(1, message.count + 1):
		in_order.append(str(i) if arrived.has(i) else "_")
	var lines := PackedStringArray(["Arrived: " + ", ".join(arrived.map(func(i) -> String: return str(i))),
		"In order: " + ", ".join(in_order)])
	if arrived.size() == message.count:
		lines.append('"%s"' % message.text)
	screen.show_desktop("From " + _name(message.from), lines)


## Where packets wait at a device: just above its first port.
func _device_position(id: String) -> Vector3:
	var device: Node = mission.devices.get(id)
	if device == null:
		return global_position
	var ports: Array = device.ports()
	var base: Vector3 = ports[0].snap_transform().origin if not ports.is_empty() else device.global_position
	return base + Vector3(0, lift, 0)


func _port_position(port: String) -> Vector3:
	var zone: Area3D = mission.zone_of.get(port)
	return zone.snap_transform().origin + Vector3(0, lift, 0) if zone else _device_position(NetworkGraph.device_of(port))


## A device's screen, taken from the mission's own screen updates.
func _screen(id: String) -> Node:
	var device: Node = mission.devices.get(id)
	var screen: Node = device.screen() if device else null
	if screen:
		mission.screens_in_use[id] = true
	return screen


func _name(id: String) -> String:
	return mission._name(id)
