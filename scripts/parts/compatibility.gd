extends RefCounted
## Whether PC parts work together. Pure functions over part specs (entries of
## data/parts_catalog.json): no scene and no state, so each rule can be tested
## on its own.
##
## A rule is called by name: check(rule, part, others) returns "" when all is
## well, or the sentence the student reads when it is not. A SnapZone with a
## `compat` rule calls it for a part dropped on it, with the specs of the
## parts already installed as `others`.

## Rules for a part going into its slot: these are about what physically fits.
const ON_DROP := ["cpu_socket", "ram_type", "storage_slot"]
## Rules for switching the PC on. "power" runs both, in this order.
const ON_POWER := ["gpu_plug", "enough_power"]
const RULES := ["cpu_socket", "ram_type", "storage_slot", "gpu_plug", "enough_power", "power"]
## What each rule needs to do its job, so the registry can tell when a rule is
## on the wrong slot: the type of part it judges ("" for any, e.g. the finger
## on the power button), and the types it compares against, which must be in
## the slots the rule's slot requires.
const NEEDS := {
	"cpu_socket": {"part": "cpu", "others": ["motherboard"]},
	"ram_type": {"part": "ram", "others": ["motherboard"]},
	"storage_slot": {"part": "storage", "others": ["motherboard"]},
	"gpu_plug": {"part": "", "others": ["gpu", "psu"]},
	"enough_power": {"part": "", "others": ["cpu", "gpu", "psu"]},
	"power": {"part": "", "others": ["cpu", "gpu", "psu"]},
}

## What the rest of the PC draws on top of the CPU and the graphics card
## (watts), and how much bigger than the total a power supply should be.
const OTHER_PARTS_WATTS := 100.0
const HEADROOM := 1.25
## Power supplies come in steps of this many watts, so advice is rounded up to one.
const WATTS_STEP := 50.0
## Lowest tier first: a build is balanced when its tiers are neighbours.
const TIERS := ["starter", "mid", "high"]
## The order parts are named in a build's summary.
const SUMMARY_ORDER := ["cpu", "gpu", "ram", "storage", "motherboard", "psu"]
## How a power plug is written in a message.
const PLUG_NAMES := {"pcie8": "8-pin PCIe", "12v2x6": "12V-2x6"}


## Runs a rule by name. `part` is the part being checked (for "power" it can
## be {}); `others` are the specs of the parts already in the build.
static func check(rule: String, part: Dictionary, others: Array) -> String:
	match rule:
		"cpu_socket":
			return cpu_socket(_pick(part, others, "cpu"), of_type(others, "motherboard"))
		"ram_type":
			return ram_type(_pick(part, others, "ram"), of_type(others, "motherboard"))
		"storage_slot":
			return storage_slot(_pick(part, others, "storage"), of_type(others, "motherboard"))
		"gpu_plug":
			return gpu_plug(_pick(part, others, "gpu"), _pick(part, others, "psu"))
		"enough_power":
			return enough_power(_pick(part, others, "cpu"), _pick(part, others, "gpu"), _pick(part, others, "psu"))
		"power":
			for power_rule in ON_POWER:
				var message := check(power_rule, part, others)
				if message != "":
					return message
			return ""
	push_error("Compatibility: there is no rule named %s" % rule)
	return ""


## The CPU's socket must be the motherboard's.
static func cpu_socket(cpu: Dictionary, board: Dictionary) -> String:
	if cpu.is_empty() or board.is_empty() or cpu.socket == board.socket:
		return ""
	return "This CPU's socket (%s) doesn't match the motherboard (%s)." % [cpu.socket, board.socket]


## The RAM's generation must be the one the motherboard's slots take.
static func ram_type(ram: Dictionary, board: Dictionary) -> String:
	if ram.is_empty() or board.is_empty() or ram.ram == board.ram:
		return ""
	return "%s RAM won't fit a %s slot: the notch is in a different place." % [ram.ram, board.ram]


## A SATA drive fits any board; an M.2 drive needs a board with an M.2 slot.
static func storage_slot(storage: Dictionary, board: Dictionary) -> String:
	if storage.is_empty() or board.is_empty() or storage.bus == "sata" or board.get("m2", false):
		return ""
	return "This board has no M.2 slot for that drive."


## The power supply must have the cable the graphics card's power socket takes.
static func gpu_plug(gpu: Dictionary, psu: Dictionary) -> String:
	if gpu.is_empty() or psu.is_empty() or gpu.plug in psu.plugs:
		return ""
	return "The %s needs a %s cable, and this power supply doesn't have one." % [gpu.name, PLUG_NAMES.get(gpu.plug, gpu.plug)]


## The power supply must cover what the parts draw, with room to spare.
static func enough_power(cpu: Dictionary, gpu: Dictionary, psu: Dictionary) -> String:
	if cpu.is_empty() or gpu.is_empty() or psu.is_empty() or psu.watts >= watts_needed(cpu, gpu):
		return ""
	return "The power supply is too small: the PC shuts off under load. You need about %d W." % [
		ceili(watts_needed(cpu, gpu) / WATTS_STEP) * int(WATTS_STEP)]


## The smallest power supply (watts) a CPU and graphics card should have.
static func watts_needed(cpu: Dictionary, gpu: Dictionary) -> float:
	return (cpu.watts + gpu.watts + OTHER_PARTS_WATTS) * HEADROOM


## True when the parts' tiers are within one step of each other: no high-end
## part next to a starter one.
static func is_balanced(parts: Array) -> bool:
	var steps := parts.map(func(part) -> int: return TIERS.find(part.get("tier", "")))
	return not steps.is_empty() and not steps.has(-1) and steps.max() - steps.min() <= 1


## A build in one line for a results card: the parts' names, the ones a
## student compares first (CPU, graphics card) in front.
## e.g. "AMD Ryzen 5 7600 + RTX 4060 Ti + DDR5-5600 2x16 GB + ..."
static func summary(parts: Array) -> String:
	var names := []
	for type in SUMMARY_ORDER:
		var part := of_type(parts, type)
		if not part.is_empty():
			names.append(part.name)
	return " + ".join(names)


## The first of `parts` that is of `type`, or {}.
static func of_type(parts: Array, type: String) -> Dictionary:
	for part in parts:
		if part.get("type", "") == type:
			return part
	return {}


## The part of `type` for a rule: the part being checked if it is one, else
## the one already in the build.
static func _pick(part: Dictionary, others: Array, type: String) -> Dictionary:
	return part if part.get("type", "") == type else of_type(others, type)
