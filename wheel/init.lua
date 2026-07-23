local Refresh = require("wheel/refresh")

modimport("scripts/wheel/wheel_widget.lua")
modimport("scripts/wheel/playerhud.lua")

package.loaded["wheel/refresh"] = Refresh
package.loaded["ui/spell_wheel_refresh"] = Refresh

return Refresh
