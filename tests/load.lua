local BM = {}
for _, file in ipairs({ "Data", "Profiler", "Codec", "Capture", "Sync", "UI", "Guild", "Core" }) do
    assert(loadfile("borjes-magasin/" .. file .. ".lua"))("borjes-magasin", BM)
end
return BM
