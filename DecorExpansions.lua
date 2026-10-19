---------------------------------------------------------------------
-- DecorSync - fixed expansion for decor, by name.
-- Anything listed here is used first, before what the game reports.
-- Use the exact expansion labels below. Names are matched ignoring case,
-- spaces and punctuation. To add more, put a line in the list.
--   Classic, Burning Crusade, Wrath of the Lich King, Cataclysm,
--   Mists of Pandaria, Warlords of Draenor, Legion, Battle for Azeroth,
--   Shadowlands, Dragonflight, The War Within, Midnight
-- Example:  ["Zandalari Ritual Drum"] = "Battle for Azeroth",
---------------------------------------------------------------------
local ADDON_NAME, ns = ...

ns.DecorExpansionList = {
}

ns.StaticExpansion = {}
for name, label in pairs(ns.DecorExpansionList) do
    ns.StaticExpansion[(tostring(name):lower():gsub("[^%w]", ""))] = label
end
