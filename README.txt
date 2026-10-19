DECORSYNC - setup

INSTALL
Copy the "DecorSync" folder into  World of Warcraft\_retail_\Interface\AddOns\
(both accounts use the same folder if they share one WoW install).
If WoW says it is out of date, tick "Load out of date AddOns" at character select.

OPEN IT
Click the minimap button (or the addon menu next to the minimap), or type /decorsync.

CHOOSE A ROLE
The first time you open the window it asks what this account does: SELLER (it owns the decor) or CRAFTER (it has your crafters).
The window then only shows what that role uses. Switch any time with the Crafter | Seller buttons at the top of the window.
- Crafter: Get decor list, the "Decor to craft" and "In stock" tabs, search, Want, CraftSim import, and the login request and profession scan in Setup.
- Seller: Send my decor, a "Tracked stock" tab (what "Send my decor" will send: each character's bags, bank, mail and auctions including TradeSkillMaster's counts, the warband bank and guild banks), and the guild bank setting in Setup.
Linking the accounts (Setup tab) is the same for both.

FIRST-TIME SETUP (you only do this once)
1. Log into a character on each account, at the same time.
2. On either account, open the Setup tab (the window opens on it until you are linked) and type
   the OTHER account's character into the box (Name-Realm, for example Alice-Frostmourne) and press Connect.
3. On the other account a pop-up asks "Is that a character on your other account?" - press Yes.
   You should see "Connected!". That's the link done. A crafter you log in with later
   will ask the same question once.

EVERY TIME
- On the account with your CRAFTERS: press "Get decor list".
  (Or on the account that owns the decor: press "Send my decor".)
- Wait for the "Receiving x/y" counter to finish.
- Open each profession window once on each crafter. Recipes are recorded automatically.
- The list in the window shows what to craft, how many, and which characters can make it.
  Use "Want" to change how many of each piece you want, and the tick box to only show
  what the character you're on can craft.

The list is saved, so you can check it later without the other account being online.

WHAT COUNTS
Only SELLABLE stock counts: decor sitting in bags, bank, mail, auction listings and the
warband bank on EVERY character of the owning account. Decor you have learned or placed in a
house is NOT counted (you can't sell it). The game only lets an addon see the character you are
logged into, so each character's holdings are remembered as you play. To get a character counted:
  - log into it once (bags are read automatically),
  - open its bank once, open its mailbox once, and open the auction house's Auctions tab once (DecorSync only reads, it never queries the AH itself).
If TradeSkillMaster is installed on the owning account, its per-character bag/bank/mail/auction
data is read too, and for each character and place the HIGHER of its number and DecorSync's own is used,
so you don't need to visit characters TSM already knows about.
/decorsync tsm shows what was read from it.
Then press "Send my decor" (or "Get decor list" on the other account). Hover a row in the
list to see Owned / Want / Need for that piece.

DECOR ID DATABASE
DecorIDs.lua (item IDs) and DecorNames.lua (decor names) hold what counts. An item counts if its ID OR its name is listed.
Bags, bank, mail, auctions, the warband bank and TSM data are filtered through them. To add more, append to either list. "/decorsync item <id>" and "/decorsync find <name>" show whether something is in the database.

GUILD BANKS (setting, off by default)
In the Seller view's Setup tab, tick "Include guild banks in my stock" (or type /decorsync guild on|off) on the
account that owns the decor. When it is ticked, decor in the guild bank tabs you can view is counted, once per guild.
Open each guild bank once and wait a few seconds while its tabs are read; it is then remembered. If TradeSkillMaster
tracks the guild bank, its numbers are used too (the higher of the two). Press "Send my decor" again after changing the setting.
/decorsync inv lists remembered guild banks, and /decorsync find <name> shows guild bank counts.

CRAFTSIM CRAFT QUEUE
Press "Import to CraftSim queue" (or /decorsync craftsim) on a crafter. Everything that character can craft and is
below your "Want" is added to CraftSim's Craft Queue, with the amount still needed. Pressing it again updates the
amounts instead of adding them twice. It only imports what the character you're logged into can craft, so do it once
per crafter. Recipe IDs are saved when a profession window is opened, so open each profession once after updating.
This reaches into CraftSim's own code (it has no public API for it), so if a CraftSim update changes things it may stop working.

LUMBER NEEDED (Decor to craft tab)
Each expansion heading shows lumber owned/needed for everything under it, e.g. 28/32 Dragonpine Lumber (red = short, green = enough).
It uses each recipe's reagents, which are recorded when a profession window is opened, so open each profession once on each crafter.

LUMBER TAB
On a crafter it also shows NEED ALL (lumber for everything short of Want) and NEED PROF (just the profession window you have open).
Shows your housing lumber (one kind per expansion) in every character's bags and bank and in the warband bank, for this account.
Bags are read at login; open each character's bank once. It is not sent to the other account.

WARBAND BANK WARNING
Only one game account can use the warband bank at a time. If you see "Warband bank: no access" in the window or a WARNING in chat
when opening a bank, your other account probably logged in first. Warband numbers are not updated (the last known ones are kept).
Log out of both, log into this account first, and open the bank again.

IN STOCK TAB
The "In stock" tab lists every decor you hold to sell (even just 1; the number is amber while it is below your "Want"), and where it is:
which character's bags / bank / mail / auction listings, or the warband bank. Hover a row for the full breakdown. The In stock and Decor to craft tabs are grouped by expansion (read from the game's item data at login, so no profession windows are needed; /decorsync expansions shows what it found, and DecorExpansions.lua overrides any that are wrong). Click an expansion heading to collapse or expand it.
The search box filters both tabs.
Both accounts must run the same DecorSync version, and the owning account has to send the list again before locations show.

IF SOMETHING GOES WRONG
- /decorsync debug on     shows what is sent and received
- /decorsync dump         shows what the housing catalog returns (send me this if the scan finds 0 decor)
- /decorsync find <name>  shows every count the addon has for a decor name, and where it came from
- /decorsync tsm         shows what was read from TradeSkillMaster (send me this if the numbers are off)
- /decorsync item <id>  shows how an item ID is resolved (catalog lookups, item class, TSM)
- /decorsync inv         shows what is remembered per character (add "clear" to forget it)
- /decorsync minimap      hides or shows the minimap button
