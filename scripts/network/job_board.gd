extends Node3D
## Distributed work (Build a Network, mission 7): one big job, split into
## tiles that the player drags onto Mac minis' Job slots. This works out how
## long the job takes and shows it on the time bar: a small InfoPanel above
## the table (a child named TimeBar) and two bars under it, the job on one
## machine and the job split across the machines that have tiles.
##
## The sums, as in the Phase 3 plan:
## - On one machine the job takes every tile one after another: tiles x 1 s.
## - Split across machines, they all work at once, so it takes as long as the
##   busiest machine: its tiles x 1 s, plus 0.5 s for the network to send
##   each machine its work (they get it at the same time).
## e.g. 12 tiles on 4 machines: "Sequential: 12 s -> Parallel: 3.5 s".

## Seconds one machine takes for one tile.
@export var tile_s := 1.0
## Seconds the network takes to send a machine its work.
@export var network_s := 0.5
## Metres of bar for each second.
@export var bar_m_per_s := 0.02

@onready var _panel: Node = get_node_or_null("TimeBar")
@onready var _sequential_bar: Node3D = get_node_or_null("SequentialBar")
@onready var _parallel_bar: Node3D = get_node_or_null("ParallelBar")


## The whole job on one machine (seconds).
func sequential_s(tiles: int) -> float:
	return tiles * tile_s


## The job split as `counts` says (tiles on each machine; 0 for one with
## none): the busiest machine's tiles, plus the network's time (seconds).
## 0 when nothing has been handed out.
func parallel_s(counts: Array) -> float:
	var most := 0
	for c in counts:
		most = maxi(most, c)
	return 0.0 if most == 0 else most * tile_s + network_s


func speedup(tiles: int, counts: Array) -> float:
	var p := parallel_s(counts)
	return 0.0 if p == 0.0 else sequential_s(tiles) / p


## True when the tiles are spread evenly: every machine within one tile of
## every other. `counts` has every machine, including those with none.
static func is_even(counts: Array) -> bool:
	if counts.is_empty():
		return false
	return counts.max() - counts.min() <= 1


## How many machines have work.
static func machines_used(counts: Array) -> int:
	return counts.filter(func(c) -> bool: return c > 0).size()


## The time bar's one line, e.g. "Sequential: 12 s -> Parallel: 3.5 s  Speedup 3.4x".
func summary(tiles: int, counts: Array) -> String:
	if parallel_s(counts) == 0.0:
		return "Sequential: %s" % _secs(sequential_s(tiles))
	return "Sequential: %s → Parallel: %s · Speedup %.1f×" % [_secs(sequential_s(tiles)), _secs(parallel_s(counts)), speedup(tiles, counts)]


## Shows the job's times for `tiles` tiles spread as `counts` (`placed` of
## them handed out so far).
func show_times(tiles: int, counts: Array, placed: int) -> void:
	var lines := PackedStringArray([summary(tiles, counts)])
	lines.append("Handed out: %d of %d · Machines: %d" % [placed, tiles, machines_used(counts)])
	if _panel:
		_panel.show_text("Time for the job", lines)
	_set_bar(_sequential_bar, sequential_s(tiles))
	_set_bar(_parallel_bar, parallel_s(counts))


func _set_bar(bar: Node3D, seconds: float) -> void:
	if bar == null:
		return
	bar.visible = seconds > 0.0
	bar.scale.x = maxf(seconds * bar_m_per_s, 0.001)


static func _secs(seconds: float) -> String:
	return ("%d s" % roundi(seconds)) if is_equal_approx(seconds, roundf(seconds)) else ("%.1f s" % seconds)
