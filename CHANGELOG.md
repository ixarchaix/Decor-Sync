# DecorSync Changelog

All notable changes between the supplied builds are recorded here, newest first.

## [0.10.1] - 2026-10-19

### Fixed
- DecorSync no longer sends its own auction house queries. It used to ask for your owned auctions when the auction house opened and after you posted an auction, which could throttle TradeSkillMaster's posting. It now only reads what the game or TSM has already fetched.

### Changed
- Auction listings are read 3 seconds after the game reports an update (was 0.5 seconds), so they land after TSM's own activity.
- Because the read is passive, a character's auctions are only picked up once the auction house's Auctions tab has been opened. `README.txt` now says so.

## [0.10.0] - 2026-10-19

### Added
- Optional guild bank support, off by default. Tick "Include guild banks in my stock" in the window's new SETTINGS section, or use `/decorsync guild on|off`, on the account that sends the list. Decor in the guild bank tabs you can view is then counted, once per guild, and shown as "guild bank (Guild Name)" in locations. `/decorsync guild` on its own says whether guild banks are included.
- Guild bank tabs are read one at a time when you open the guild bank and are remembered per guild, so open each guild bank once and wait a few seconds. The tab you're looking at is re-read after deposits and withdrawals. If TradeSkillMaster tracks the guild bank, the higher of the two numbers is used. Press "Send my decor" again after changing the setting.
- An "Import to CraftSim queue" button and `/decorsync craftsim`. Run it on a crafter to add everything that character can craft and is short of (Want minus Owned) to CraftSim's Craft Queue, with the amount still needed. Pressing it again updates the amounts instead of adding them twice. It imports a few recipes at a time, reports how many were added, updated, skipped or failed, and says so if CraftSim isn't available.
- Recipe IDs are now saved when a profession window is opened, which the CraftSim import needs. Recipes recorded in earlier builds have none, so open each profession window once on each crafter after updating.
- The `.toc` lists CraftSim as an optional dependency, alongside TradeSkillMaster.

### Changed
- `/decorsync inv` lists remembered guild banks and whether each is included, `/decorsync find <name>` shows guild bank counts, and `/decorsync inv clear` also forgets guild banks.
- `/decorsync reset` also clears the saved recipe IDs.
- The window is taller (620 x 704, from 620 x 652). The footer now has a SETTINGS section with the guild bank tick box, the "Ask for a fresh list when I log in" tick box, and the new CraftSim button beside "Scan profession window".
- The `/decorsync` help text lists `craftsim` and `guild on|off`.
- `README.txt` has new "Guild banks" and "CraftSim craft queue" sections.

## [0.9.0] - 2026-10-19

### Added
- A database of decor names in a new file, `DecorNames.lua` (343 names), loaded by the `.toc`. Names are matched ignoring case, spaces and punctuation. To add more decor, append names to the list in that file.
- `/decorsync find <text>` also reports whether the name is in the decor name database.

### Changed
- An item now counts as sellable decor if its item ID is in `DecorIDs.lua` or its name is in `DecorNames.lua`. Previously only the ID list was used. The game's catalog still has to recognise the item.
- `/decorsync item <id>` reports ID and name database membership separately and notes that one match is enough to be counted.
- `README.txt` describes both databases.

## [0.8.0] - 2026-10-19

### Added
- A database of decor item IDs in a new file, `DecorIDs.lua` (343 IDs so far), loaded by the `.toc`. To add more decor, append item IDs to the list in that file.
- `/decorsync item <id>` now also reports whether the ID is in the decor ID database.

### Changed
- Only items listed in the decor ID database are counted as sellable decor. Bag, bank, mail and auction scans, the warband bank and TradeSkillMaster data are all filtered through it, and anything not listed is ignored.
- `README.txt` has a new "Decor ID database" section.

## [0.7.0] - 2026-10-19

### Added
- The "In stock" tab is grouped by profession, using the recipes you've recorded. Each group has a heading row with its count, and pieces with no recorded crafter go last under "Other (no recorded crafter)". Pieces are sorted by profession, then name.
- `/decorsync item <id>` shows how an item ID is resolved: each catalog lookup and its result, what DecorSync finally makes of it, the item's name and class, how many this character carries, and which TradeSkillMaster characters hold it.

### Fixed
- Sellable decor that the game's "owned" catalog lookup didn't recognise could be missed. The lookup may only answer for decor you've already learned, so DecorSync now also tries the plain lookup and an item link, and as a last resort accepts an item of the Housing class under its item name. This applies to bag, bank, mail and auction scans, to TradeSkillMaster data, and to recording crafted decor recipes.

### Changed
- The `/decorsync` help text lists `item <id>`, and `README.txt` describes the profession grouping and the new command.

## [0.6.1] - 2026-10-19

### Changed
- The "In stock" tab now lists every decor you hold to sell, even just one, instead of only pieces at or above your "Want" number.
- The owned count in an In stock row is green when it meets your "Want" number and amber while it is below it. The hover tooltip adds how many are short, for example "(2 short)".
- The empty In stock message is now "No sellable decor found yet."
- `README.txt` describes the new In stock behaviour.

## [0.6.0] - 2026-10-19

### Changed
- "Owned" now means sellable stock only: decor in bags, bank, mail and auction listings on every character of the owning account, plus the warband bank. Pressing "Send my decor" collects these and no longer scans the housing catalog, and it freshens the bags of the character you're on first.
- The "Decor owned" stat card is now "Sellable stock (other account)". The Want tooltip, the In stock tab text and the empty-list message ("No sellable stock at your Want number yet.") are reworded to match.
- The "nothing found" message when sending now says no sellable decor was found in bags, bank, mail, auctions or the warband bank, and suggests visiting each seller or using TradeSkillMaster.
- `/decorsync find` labels the housing catalog line "(learned/placed, NOT counted)".
- `README.txt` rewritten for what counts and the In stock tab.

### Fixed
- When TradeSkillMaster is installed, a gap in either source no longer hides decor. For each character and place (bags, bank, mail, auctions) DecorSync now compares its own scan with TSM's numbers and uses the higher one, instead of letting TSM replace everything for characters it knows. Places only TSM tracks (such as the reagent bank) are added as they are, and characters only TSM knows still use TSM's data.

### Removed
- Decor you've learned or placed in a house is no longer counted or sent, since it can't be sold. "Housing storage" and "placed in house" no longer appear as locations.

## [0.5.0] - 2026-10-19

### Added
- An "In stock" tab next to "Decor to craft". It lists the decor you already own at least your "Want" number of, with the owned count and where it is.
- The decor list now carries where each piece is: housing storage, placed in a house, each character's bags, bank, reagent bank, mail and auction listings, and the warband bank. Hover a row on the In stock tab for the full breakdown. A piece with more than 8 locations shows the biggest ones and groups the rest as "more".
- A search box above the list that filters both tabs by decor name. Escape clears it.
- Each tab shows its count, for example "Decor to craft 12" and "In stock 40".
- Empty-list messages for the new cases: "Nothing matches that search." and "Nothing is stocked at your Want number yet."

### Changed
- The transfer protocol is now version 2 so locations can be sent. Both accounts must update, and the owning account has to send its list again before locations show. A pre-update list reads "location unknown", and an account on the old version gets the "different DecorSync version" message.
- The "Only what this character can craft" tick box moved to the left of a new filter row under the tabs, and also applies to the In stock tab.
- The window is taller (620 x 652, from 620 x 612) to fit the filter row, and the list sits lower.
- The column headers follow the tab: NEED and WHO CAN CRAFT IT on Decor to craft, OWNED and WHERE IT IS on In stock. In stock rows get a blue bar and a green owned count.
- `README.txt` has a new section describing the In stock tab.

## [0.4.0] - 2026-10-19

### Added
- Decor held outside housing storage now counts as owned. The housing catalog can't see decor sitting in bags, bank, mail or auction listings, so the list you send now also includes decor in all of those on every character of the owning account, plus the warband bank. Sold auctions are not counted.
- Each character's bags, bank, mail and auctions are remembered in the saved data as you play, because the game only shows the character you're logged into. Bags are read at login and whenever they change, the bank when you open it, mail when you open the mailbox, and auctions when you open the auction house or post something.
- Optional TradeSkillMaster support. If TSM is installed, its per-character bag, bank, mail and auction data is used for every character it knows, so you don't need to log into each one. Characters TSM doesn't know still use what DecorSync saw itself. The `.toc` now lists TradeSkillMaster as an optional dependency.
- `/decorsync find <text>` lists every number DecorSync has for a decor name and where it came from: bags, bank, mail, auctions, warband bank, TSM, the received list, recipes and the housing catalog.
- `/decorsync tsm` shows what was read from TradeSkillMaster, or the first few keys it found if no decor was recognised.
- `/decorsync inv` shows what is remembered for each character and when it was last updated. `/decorsync inv clear` forgets it and re-reads this character's bags.
- Two stat cards above the list: "Decor to craft" (how many pieces are needed, with how many craftable decor are recorded) and "Decor owned (other account)" (how many entries, who sent them and how long ago).
- Hovering a row now shows Owned / Want / Need for that piece, plus who can craft it.
- Close button (×) in the window's title bar.

### Changed
- The window is restyled to match Regional Edge's "Midnight" theme: flat dark navy panels with 1px borders, a connection card grouping the name box and buttons, an underlined "Decor to craft" tab, a lime bar and amber "Need" number on each row, a slim scroll bar, and custom buttons and tick boxes. It is larger (620 x 612) and shows 10 taller rows instead of 12.
- Tooltips use the addon's own style instead of the default game tooltip, including on the minimap button.
- The footer line ("Decor list: x entries from...") is replaced by the stat cards.
- The `/decorsync` help text lists `find`, `inv` and `tsm`.
- `README.txt` explains what counts as owned and how to get each character counted, and lists the new troubleshooting commands.

## [0.3.0] - 2026-10-19

### Added
- A window for everything, opened with `/decorsync`, a minimap button, or the addon menu next to the minimap (new `UI.lua`). The `.toc` now has an icon and addon menu entries.
- Connect box and button for your other account's character (Name-Realm), plus "Get decor list", "Send my decor" and "Scan profession window" buttons, each with a tooltip.
- Live status line and a "Sending x/y" / "Receiving x/y" counter while a list is transferring.
- "Decor to craft" list showing how many are needed and which characters can craft each piece, with a scroll bar and a hover tooltip.
- "Want" counter (plus and minus buttons) replacing `/decorsync target`.
- "Only what this character can craft" tick box and "Ask for a fresh list when I log in" tick box in the window.
- Pairing pop-up: the first time an unknown character contacts you it asks "Is that a character on your other account?". Only characters you answer Yes for are accepted from then on.
- `/decorsync minimap` hides or shows the minimap button.
- "Already sending" protection, so pressing Send twice doesn't start two transfers.
- Transfers that stall for over a minute are dropped, so a stuck "Receiving" counter clears itself.

### Changed
- Crafters are now recorded with their realm (Name-Realm). On first load the old recipe list is cleared once and needs re-recording by opening each profession window.
- Whichever character connects, requests or sends to you becomes your partner automatically after pairing, so `/decorsync partner` is no longer needed.
- Messages now also appear in the window's status line, and many were reworded (for example "Connected!", "confirmed: your decor list was delivered").
- `/decorsync needed` still prints the craft list in chat but now uses the same list as the window.
- `/decorsync reset` clears the recorded recipes (this replaces `resetrecipes`).
- `README.txt` rewritten for the window-based setup.

### Removed
- Community chat route and its commands (`/decorsync community`, `community use`, `community off`), including joining the community channel at login. Whispers to a Name-Realm are the only route now, and any saved community setting is cleared on load.
- Slash commands now covered by the window: `partner`, `ping`, `send`, `request`, `recipes`, `target`, `auto` and `status`.
- The "Ignored a message from..." chat notice, replaced by the pairing pop-up.

## [0.2.1] - 2026-10-19

### Fixed
- Debug output (`/decorsync debug on`) no longer garbles messages that contain a `|` character. WoW chat treats `|` as the start of a formatting code, so it is now doubled to display literally.

## [0.2.0] - 2026-10-19

### Added
- `/decorsync debug on|off` prints every addon message sent and received, including the result code the game returns for each send. Useful when a connection isn't working.
- Joining a community now also adds its chat channel to your main chat window, not just to the account.

### Changed
- `/decorsync ping` now says which route it is using before sending: the community and its channel number (or "NOT FOUND (not joined)"), or a whisper to your partner, with a note that whispers need the same realm and faction.
- The `ping` messages now say "queued" and "a few seconds" so it's clearer the reply isn't instant.
- Joining the community channel now goes through one shared routine, used at login and by `/decorsync community use`, so both behave the same.
- The `/decorsync` help text lists the new `debug` command.

## [0.1.0] - 2026-10-19

First supplied build.

### Added
- Account A (the decor owner) whispers its owned housing decor list to a character on Account B (the crafters). Account B saves it, so the list can be checked later even when Account A is offline.
- Community chat route as an alternative to whispers, so realm and faction don't matter (`/decorsync community`, `/decorsync community use <number>`, `off`).
- `/decorsync partner <name>` links a character on your other account (set on both accounts).
- `/decorsync send` sends your decor to the partner, and `/decorsync request` asks the partner to send it.
- Decor recipes are recorded automatically when you open a profession window (`/decorsync recipes` to record manually).
- `/decorsync needed` shows what to craft and which characters can craft it.
- `/decorsync target N` sets how many of each decor you want (default 1).
- `/decorsync auto on|off` asks the partner for a fresh list at login.
- `/decorsync ping` tests the connection to your partner.
- `/decorsync status`, `/decorsync dump` (shows what the housing catalog returns) and `/decorsync resetrecipes`.
- Messages are sent through a slow, polite queue that retries when the game throttles addon messages.
- Setup instructions in `README.txt`.
