# borjes-magasin

A dependency-free WoW Forever guild ledger, **version 0.3.6**, for Interface 16001.
The roster and statistics now come from the client and guild addon messages.
There are no built-in fictional members or statistics.

## Install and share

Copy the `borjes-magasin` folder into `_forever_/Interface/AddOns/`, enable it,
and `/reload`. Give the same ZIP to guild members and have them do the same.
Each character shares only its own snapshot on WoW's hidden **GUILD addon
channel**. Members without this addon receive no visible chat messages.
No companion application, account, web service, HTTP call or external database
is involved.

Open the standard Guild & Communities window and click its **bear tab**.
`/borjes`, `/bm`, `/borjes-magasin`, and the minimap bear also open that tab.
The ledger follows the normal guild window; native tabs and closing still work.
Opening during combat waits until combat ends. Drag the minimap bear along the
outer ring to reposition it.

Version 0.3.1 fixes the guild-chat scrollbar showing above the ledger. Its
native HIGH drawing layer is temporarily lowered while the bear tab is active,
then restored on native navigation, closing or minimizing the guild window.
Chat visibility, scroll position and the other guild controls are preserved.

Sharing starts enabled. **Pause sharing** stops sending and receiving; local
tracking continues. Existing copies on other players' computers remain there.
**Sync now** asks online addon users to publish their own latest snapshot.
Discovery requests are limited to one every 30 seconds. A snapshot takes several
seconds to arrive because messages are queued and throttled.

Version 0.3.6 fixes Forever's **first name + surname** identities. For example,
`Suer Fisk` is one character; `Fisk` is a surname, not a realm. The self row,
guild roster, party/raid filter, PvP names and addon-message senders retain both
words. Spaced and hyphenated full names match the same character, while people
sharing only a first name or surname stay distinct. Incomplete names are never
matched by guessing. This replaces the incorrect realm assumption in earlier
versions, which could show the player twice and reject party/sync matches.
Existing local history is retained, and cached full-name entries with the old
extra suffix migrate to the corrected identity, keeping the newest snapshot.
Guildmates should update too so both clients handle names correctly.

**Sync now** immediately shows **Sync queued**, then packet progress and a count
of received guild snapshots. Once your own snapshot is sent, it shows **Waiting
for guild replies** or **No guild replies received** after 90 seconds without
a response. This does not claim other members have received your data or that
they lack the addon. Paused sharing, missing guild membership and client message
restrictions are shown explicitly. Progress updates do not rebuild the roster.

Use `/bm debug` for live sync and party-filter diagnostics.
The local report records the running version, queue state, packet counters,
rejection reasons, API errors, and the guild/party names used for matching.
It saves to `BorjesMagasinDB.lastSyncReport` on `/reload` or logout, never to guild
chat. The event history is capped at 24 entries and contains no snapshot payloads.
An error in a send timer now stops the queue with a visible error instead of
leaving it stuck on “Sync queued”; a manual request can retry. A client restriction
is recorded and remains visible after retries expire, rather than being replaced
with a generic timeout. Correct names cannot override a client message restriction.

The **Settings** tab offers a heartbeat of **Off, 5, 10, 15 or 30 minutes**.
It defaults to **Off**, including upgrades from versions with a fixed heartbeat.
The choice is saved for this account. Changing it starts a new interval and
cancels any unfinished heartbeat transfer. Pause sharing also stops heartbeats;
resuming starts a fresh interval without an immediate broadcast.

Login/reload and logout still sync when the heartbeat is off. Guildmates' login
or manual requests can also receive your latest snapshot. A heartbeat publishes
only your own snapshot; it does not ask the entire guild to send theirs.
Logout starts a paced transfer during the countdown, then attempts any remaining
data at final logout. This is **best effort**: an instant exit, disconnect or
client throttle can prevent delivery. Your own latest data is still saved locally
on normal logout/reload. Canceling logout stops its unfinished transfer.

## What is shown

- **Guild roster:** actual members, including members with no received snapshot.
  Unknown values are marked Unknown/No snapshot, rather than zero. An offline
  member keeps the last snapshot received on this computer. Lack of a snapshot
  does not prove the addon is absent. The party filter uses your actual party,
  or your five-person subgroup in a raid; only guild members appear, plus you.
- **World PvP:** personal or own-pet killing blows observed through `PARTY_KILL`
  while outside instances. Non-gray enemies at your level minus five or higher
  count as qualifying; gray enemies count as ganks. Lower non-gray enemies are
  out of range. Unknown/secret levels or missing gray classification remain
  unclassified. Enemy identity/level must have been observed on a target,
  mouseover or nameplate within 30 seconds. Duplicate death events within five
  seconds are ignored. Battlegrounds, arenas and all other instances are
  excluded. Counters begin when this live version is first used; historical
  kills cannot be reconstructed. Last 7 days means the current UTC day and six
  previous UTC days. All time survives reloads and guild changes.
- **Dungeon quests:** a curated set of 24 quests across Deadmines, Wailing
  Caverns, Stockade, Scarlet Monastery, Razorfen Downs and Zul'Farrak, including
  Forever's *Past Due*. Completion, log presence, ready-to-turn-in status and
  completed-objective counts come from the character's quest APIs. Known hard
  prerequisites and faction/minimum-level restrictions are checked. "Not in
  log" does not assert the quest is available. This is not a complete Forever
  quest database; the four-column layout currently shows four quests per dungeon.
- **Gold:** copper-accurate personal balances, known-balance totals/averages,
  and the last observed balance on each of the past seven UTC days. Unobserved
  days stay blank/Unknown. No bank inventories or transaction history is read.
- **Gear:** all 19 equipped inventory slots, preserving item strings including
  enchants and modifiers, with normal item tooltips. Empty and unknown slots
  are distinct. Item names/icons load from the receiving client's item cache.

Gold, equipment and quests update locally on their relevant client events.
Opening the character pane also refreshes your local snapshot. These updates,
PvP kills, zoning and roster changes do not trigger a broadcast. Login, logout,
manual requests and an optional heartbeat are the sync points. Data is captured
again before sending. Each view shows snapshot age; guild roster online status
is separate from snapshot freshness.

Two users need to be online in the same guild at overlapping times to exchange
snapshots. This version does not relay third-party profiles, so a newly installed
client cannot recover offline members' snapshots from another guild member.
Members report their own counters; this is a cooperative guild ledger, not a
server-authoritative anti-cheat leaderboard. Client restrictions are respected
and reported in the panel; they never trigger a visible-chat fallback.

## Performance and local profiling

Version 0.3.2 defers roster rendering while the ledger is closed, combines
visible update bursts into one refresh, resolves gear only for the member being
viewed, and caches item metadata. Unrelated item-cache events no longer rebuild
the roster. Pending item reads are throttled and refresh when that item loads.

Version 0.3.3 removes idle sync polling, the 30-second background capture and
change-triggered broadcasts. A send timer runs only while a transfer is queued;
failed requests stop retrying after two minutes. The heartbeat uses one timer per
chosen interval. With heartbeat off and no transfer queued, sync does no idle
work. Frame sampling runs only during a performance capture.

The first login after a version upgrade records a **120-second local profile**.
It stops automatically and saves a compact report in `BorjesMagasinDB.lastProfile`.
`/bm profile report` prints it in your own chat window. `/bm profile start` starts
another two-minute capture; `/bm profile stop` ends it early and displays results.
Logout/reload also saves a partial capture.

The report records function call counts, total/average/worst milliseconds, event counts,
and frames taking longer than 50 ms. Function timings include nested calls and
must not be added together. Total means all calls across the entire capture,
not milliseconds per frame; worst call is one invocation. Frame delays describe
the whole client, so they do
not establish that this addon caused every slow frame. The profiler does not
change WoW's global `scriptProfile` setting, collect messages/member details, or
send results to guildmates or any server.

## Commands and storage

- `/borjes`: toggle the guild ledger.
- `/borjes sync`: refresh your data and request online members' snapshots.
- `/borjes share`: pause/resume guild data sharing.
- `/borjes reset`: reset search, party filter and obsolete positioning settings;
  keep actual statistics and snapshots.
- `/borjes help`: show commands.

`BorjesMagasinDB` saves UI preferences, each local character's snapshot and
counters, and received snapshots separated by guild and realm. Data for former
guilds is not displayed or sent in a new guild. Old prototype preferences migrate;
fictional data was never saved and is not carried into the live roster.
Normal WoW logout/reload writes SavedVariables; an abnormal client termination
can lose changes made since the last save.

The teddy-bear icon is the Börjes Magasin Discord server image, chosen by the
user. The original is in `assets/discord-server-icon.webp`; the runtime texture
is `Textures/MinimapIcon.tga`. Its PNG copy is in the user's Downloads folder.

## Implementation and protocol

`Data.lua` contains the curated quest catalog and view model; `Capture.lua`
collects local data and resolves guild/party membership; `Codec.lua` implements
bounded length-prefixed arrays/strings; `Sync.lua` implements versioned discovery,
chunk assembly and rate-limited sends. `UI.lua`, `Guild.lua` and `Core.lua` handle
the existing compact guild panel, native UI integration and events.

Prefix `BorjesMagasin1`, protocol 1: `1|H` requests snapshots;
`1|S|transfer-id|part|count|chunk` sends a snapshot. Chunks contain at most 180
bytes, total snapshots at most 16,000 bytes, with no more than one packet per
0.4 seconds during ordinary transfers. Final logout makes one bounded synchronous
attempt and stops on the first send failure, since later timers cannot run.
Receivers accept only current guild-roster senders on the GUILD
channel; payloads cannot choose a profile owner. Complete snapshots undergo
schema, size, numeric, timestamp, text and item-string validation. There is no
`loadstring`, received code execution, or arbitrary hyperlink execution.
One assembly per sender, at most 64 concurrent assemblies, expires after 90
seconds. Missing chunks leave the previous complete snapshot intact; a later
enabled heartbeat, login or manual sync can repair the loss. Guild changes discard
pending traffic and restart a configured heartbeat interval; they do not send an
immediate snapshot. Expired incoming assemblies are cleaned up on the next message.

Forever API references:
[chat](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua),
[chat result enums](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatConstantsDocumentation.lua),
[club roster](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ClubDocumentation.lua),
[quest log](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua),
[unit events](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua),
[session events](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SystemDocumentation.lua).
Quest IDs, faction/minimum-level facts and required preceding quests were checked
against the installed ForeverDungeonJournal 2.0 data on 2026-11-10. The addon does
not require that addon or Questie at runtime.

## Verification

Run from this project directory:

```sh
luac5.1 -p borjes-magasin/*.lua
lua5.1 tests/test.lua
lua5.1 tests/sync.lua
lua5.1 tests/performance.lua
lua5.1 tests/settings.lua
lua5.1 tests/realm.lua
lua5.1 tests/surnames.lua
lua5.1 tests/diagnostics.lua
for scenario in preloaded late failed combat; do lua5.1 tests/bootstrap.lua "$scenario"; done
python tests/render_mock.py
```

Tests exercise independent client environments connected through simulated addon
packets: discovery, full gear/quest/gold/counter transfer, throttling, reordered
and missing chunks, malformed input, sender validation, reload persistence,
sharing pauses, client restrictions, guild changes and date rollover. Capture
checks include quest states, money/equipment/character-pane events, restricted
values, gray and qualifying kills, unknown levels, own pets, duplication and
instance exclusion. A 203-member stress test checks lazy gear reads, hidden-window inactivity, coalesced updates, item-cache invalidation, and the profiler lifecycle. UI tests retain filtering, sorting, tooltips, empty rosters,
widget reuse, minimap placement, native guild navigation, combat deferral and
load ordering/failure recovery. Mock previews are not in-game screenshots.
Forever surname tests reproduce the split unit-name API results and spaced guild
roster observed in the actual client. They check one self row, party/raid filters,
same-first-name and same-surname members, accented names, spaced/hyphenated senders,
two-client exchange, incomplete-name rejection, and saved-history/cache migration.
Separate compatibility tests retain conventional Name-Realm handling for clients
without regional names. Timer-error tests cover stopped queues and manual recovery.

Actual server delivery still requires two online guild members with this version:
reload both clients, open `/borjes`, use Sync now, wait for snapshots, then change
gear/gold, sync manually or wait for an enabled heartbeat, and verify the receiving view. Test a known world-PvP killing blow and
quest update as well. Automated tests cannot prove live server behavior.
