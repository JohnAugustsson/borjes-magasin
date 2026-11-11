local _, BM = ...
-- Length-prefixed strings and arrays; never evaluate received Lua or hyperlinks.
local MAX = 16000
BM.MAX_WIRE_BYTES = MAX
function BM.Encode(value)
    local nodes = 0
    local function encode(v, depth)
        nodes = nodes + 1
        assert(depth <= 7 and nodes <= 1400, "Payload too complex")
        if type(v) == "string" then assert(#v <= 1024 and not v:find("%z")); return "s" .. #v .. ":" .. v end
        if type(v) == "number" then assert(BM.Integer(v, 0, 1000000000000)); return "n" .. string.format("%.0f", v) .. ":" end
        if v == false then return "f" end
        assert(type(v) == "table" and #v <= 128, "Unsupported payload type")
        local parts = { "a" .. #v .. ":" }
        for i = 1, #v do parts[#parts + 1] = encode(v[i], depth + 1) end
        return table.concat(parts)
    end
    local ok, result = pcall(encode, value, 0)
    if ok and #result <= MAX then return result end
end
function BM.Decode(s)
    if type(s) ~= "string" or #s > MAX or s:find("%z") then return nil end
    local pos, nodes = 1, 0
    local function decode(depth)
        nodes = nodes + 1
        assert(depth <= 7 and nodes <= 1400 and pos <= #s)
        local tag = s:sub(pos, pos); pos = pos + 1
        if tag == "f" then return false end
        local ending = s:find(":", pos, true)
        assert(ending and ending - pos <= 13)
        local digits = s:sub(pos, ending - 1); assert(digits:match("^%d+$"))
        local n = tonumber(digits); pos = ending + 1
        if tag == "n" then assert(n <= 1000000000000); return n end
        if tag == "s" then
            assert(n <= 1024 and pos + n - 1 <= #s)
            local result = s:sub(pos, pos + n - 1); pos = pos + n; return result
        end
        assert(tag == "a" and n <= 128)
        local result = {}; for i = 1, n do result[i] = decode(depth + 1) end
        return result
    end
    local ok, result = pcall(decode, 0)
    if ok and pos == #s + 1 then return result end
end
function BM.PackProfile(p, forComparison)
    return BM.Encode({ 1, forComparison and 0 or p.at, p.level, p.class, p.zone, p.gold or false,
        p.items, p.quests, { p.pvp.since, p.pvp.allKills, p.pvp.allGanks, p.pvp.days, p.pvp.recent }, p.history })
end
local function array(v, count) return type(v) == "table" and #v == count end
local function text(v, max) return type(v) == "string" and #v <= max and BM.Text(v, max) == v end
local function number(v, max) return BM.Integer(v, 0, max or 1000000000) end
function BM.UnpackProfile(s)
    local v = BM.Decode(s)
    if not array(v, 10) or v[1] ~= 1 or not number(v[2], 4102444800) then return end
    if not BM.Integer(v[2], 1, BM.Now() + 300) or not BM.Integer(v[3], 1, 100) or not BM.ClassColors[v[4]]
        or not text(v[5], 96) or (v[6] ~= false and not number(v[6], 100000000000)) then return end
    if not array(v[7], 19) or not array(v[8], #BM.QuestList) or not array(v[9], 5) or type(v[10]) ~= "table" or #v[10] > 7 then return end
    for _, item in ipairs(v[7]) do if item ~= false and item ~= "" and (not BM.ItemString(item) or BM.ItemString(item) ~= item) then return end end
    for _, q in ipairs(v[8]) do if not array(q, 2) or not BM.Integer(q[1], 0, 6) or not text(q[2], 160) then return end end
    local pvp = v[9]
    if not BM.Integer(pvp[1], 1, v[2]) or not number(pvp[2]) or not number(pvp[3]) or type(pvp[4]) ~= "table" or #pvp[4] > 7
        or type(pvp[5]) ~= "table" or #pvp[5] > 8 then return end
    local seen, sumKills, sumGanks = {}, 0, 0
    for _, d in ipairs(pvp[4]) do
        if not array(d, 3) or not BM.Integer(d[1], 0, math.floor(v[2] / 86400)) or seen[d[1]] or not number(d[2]) or not number(d[3]) then return end
        seen[d[1]] = true; sumKills = sumKills + d[2]; sumGanks = sumGanks + d[3]
    end
    if sumKills > pvp[2] or sumGanks > pvp[3] then return end
    local kinds = { Qualifying = true, Gank = true, Unclassified = true, ["Out of range"] = true }
    for _, k in ipairs(pvp[5]) do
        if not array(k, 5) or not text(k[1], 96) or not number(k[2], 100) or not text(k[3], 96) or not BM.Integer(k[4], 1, v[2]) or not kinds[k[5]] then return end
    end
    seen = {}
    for _, d in ipairs(v[10]) do
        if not array(d, 2) or not BM.Integer(d[1], 0, math.floor(v[2] / 86400)) or seen[d[1]] or not number(d[2], 100000000000) then return end
        seen[d[1]] = true
    end
    return { at = v[2], level = v[3], class = v[4], zone = v[5], gold = v[6] ~= false and v[6] or nil,
        items = v[7], quests = v[8], pvp = { since = pvp[1], allKills = pvp[2], allGanks = pvp[3], days = pvp[4], recent = pvp[5] }, history = v[10] }
end
