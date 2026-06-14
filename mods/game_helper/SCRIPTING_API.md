# AstraClient — Scripting API (`bot.*`)

The **Script** tab (in the Helper window) lets you write your own Lua scripts.

## How scripts run

- Each script's **file body runs exactly once** — the moment the script is **enabled** ("loaded"). Use it to set up state and register your timers.
- For recurring work, register a **`Timer(intervalMs, fn)`** (see below). It runs `fn` every `intervalMs` while the script stays loaded. There is **no** implicit 200 ms loop anymore.
- Each script has its own persistent table **`storage`** — use it to keep state between ticks (it is wiped on relog, not saved to disk).
- Errors are caught. A script that errors **5 times** is auto‑disabled (which also stops its timers) so it can't spam the console.
- Scripts run in a sandbox that also gives you the normal client globals (`g_game`, `g_map`, `math`, `string`, `table`, …) if you need something not in `bot`.

### Scheduling — `Timer`
`Timer(intervalMs, fn)` is a global available to every script.

```lua
print("loaded once")              -- body: runs a single time on load

Timer(1000, function()            -- runs every 1000 ms while loaded
  if bot.hpp() < 50 then bot.useItem(266) end
end)
```

- The first tick happens **after** one `intervalMs` (not immediately). Do anything you need right away in the body.
- Register **as many timers as you like** (e.g. one at 250 ms for healing, one at 2000 ms for looting).
- It returns a handle: call **`handle:stop()`** to cancel just that timer. All of a script's timers are cancelled automatically when it is unloaded, errors out, or you relog.

### Controls
- **New / Rename / Delete** — manage scripts (right‑click a script in the list too).
- **Enable / Disable** — double‑click a script, or use the button. Enabling runs the body once and starts its timers; disabling stops them.
- **Run** — run the selected script once, right now (good for testing).
- **Save** — save the editor's code (recompiles it if the script is enabled).

---

## API reference

`pos` is a table `{x=, y=, z=}`. `creature` is a Creature object (it has `:getName()`, `:getPosition()`, `:getHealthPercent()`, `:isMonster()`, `:isPlayer()`, …).

### Player / state
| Function | Returns | Description |
|---|---|---|
| `bot.player()` | LocalPlayer or nil | The local player object. |
| `bot.online()` | bool | True if in game with a player. |
| `bot.pos()` | pos or nil | Your current position. |
| `bot.name()` | string | Your character name. |
| `bot.hp()` / `bot.maxhp()` / `bot.hpp()` | number | Health / max health / health %. |
| `bot.mp()` / `bot.maxmp()` / `bot.mpp()` | number | Mana / max mana / mana %. |
| `bot.cap()` | number | Free capacity. |
| `bot.skull()` | number | Your skull id (see SkullRed/SkullBlack constants). |

### Movement
| Function | Returns | Description |
|---|---|---|
| `bot.walk(pos)` | — | Auto‑walk to `pos` (native pathfinder; same floor). |
| `bot.stopWalk()` | — | Stop auto‑walking. |
| `bot.walking()` | bool | True while auto‑walking. |
| `bot.dist(a, b)` | number | Chebyshev (tile) distance. `a` defaults to your position. |

### World
| Function | Returns | Description |
|---|---|---|
| `bot.tile(pos)` | Tile or nil | The tile at `pos`. |
| `bot.creatures(range)` | list | Living **monsters** within `range` tiles (default 7). |
| `bot.players(range)` | list | Other **players** within `range` tiles (default 7). |
| `bot.target()` | creature or nil | The creature you are currently attacking. |
| `bot.attack(creature)` | — | Start attacking `creature`. |

### Items / actions
| Function | Returns | Description |
|---|---|---|
| `bot.itemCount(id)` | number | How many of item `id` you carry. |
| `bot.useItem(id)` | — | Use an inventory item (e.g. a potion). |
| `bot.useItemOn(id, target)` | — | Use inventory item `id` on a creature/thing. |
| `bot.use(pos)` | — | Use the top usable object at `pos` (lever, ladder…). |
| `bot.say(text)` | — | Say text / cast a spell by words (e.g. `bot.say("exura")`). |

### Timing / logging
| Function | Returns | Description |
|---|---|---|
| `bot.now()` | number | Monotonic milliseconds (for your own timing math). |
| `Timer(ms, fn)` | handle | **Global.** Run `fn` every `ms` while loaded. `handle:stop()` cancels it. See *Scheduling* above. |
| `bot.log(...)` | — | Print to the console, prefixed with the script name. (`print` also works.) |

### Cavebot control — `bot.cavebot.*`
| Function | Returns | Description |
|---|---|---|
| `bot.cavebot.enabled()` | bool | Is the cavebot running? |
| `bot.cavebot.enable()` / `disable()` / `toggle()` | — | Turn the cavebot on/off. |
| `bot.cavebot.gotoTab(name)` | bool | Switch to waypoint tab `name` (e.g. `"Refill"`); restarts that tab's loop. |
| `bot.cavebot.tab()` | string | Current waypoint tab name. |
| `bot.cavebot.tabs()` | list | All waypoint tab names. |
| `bot.cavebot.status()` | string | The cavebot status text (e.g. `"Running 3/12"`). |

### Helper control — `bot.helper.*`
| Function | Returns | Description |
|---|---|---|
| `bot.helper.enabled()` | bool | Is the Helper (healing/etc.) on? |
| `bot.helper.shooter()` / `target()` | bool | Is the magic shooter / auto‑target on? |
| `bot.helper.setShooter(on)` / `setTarget(on)` | — | Turn the magic shooter / auto‑target on/off. |

---

## Examples

**Re‑pot mana when low (every 800 ms):**
```lua
Timer(800, function()
  if bot.mpp() < 40 and bot.itemCount(268) > 0 then
    bot.useItem(268)        -- mana potion
  end
end)
```

**Switch the cavebot to a "Refill" tab when out of potions, back to "Hunt" otherwise:**
```lua
Timer(1000, function()
  if bot.itemCount(268) == 0 then
    if bot.cavebot.tab() ~= "Refill" then bot.cavebot.gotoTab("Refill") end
  elseif bot.cavebot.tab() ~= "Hunt" then
    bot.cavebot.gotoTab("Hunt")
  end
end)
```

**Turn off the shooter while a player is on screen (anti‑PK), re‑enable when clear:**
```lua
Timer(500, function()
  local pk = #bot.players(8) > 0
  bot.helper.setShooter(not pk)
  if pk then
    bot.log("player nearby!", bot.players(8)[1]:getName())
  end
end)
```

**Count kills using `storage` (persists between ticks). Two timers, different rates:**
```lua
storage.kills = storage.kills or 0

Timer(250, function()
  local t = bot.target()
  if t and t:getHealthPercent() <= 0 then storage.kills = storage.kills + 1 end
end)

Timer(10000, function()
  bot.log("kills so far:", storage.kills)
end)
```
