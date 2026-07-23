local skilltree_prefabs = require("reticule/prefabs")
local domain_expansion_reticule = require("reticule/domain_expansion_reticule")

-- Each Prefab must be its own return value; unpack() only contributes its first value here.
return skilltree_prefabs[1],
	skilltree_prefabs[2],
	skilltree_prefabs[3],
	skilltree_prefabs[4],
	domain_expansion_reticule
