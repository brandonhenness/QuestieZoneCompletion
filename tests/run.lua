local passed, failed = 0, 0

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function test(name, callback)
    local ok, message = pcall(callback)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(message))
    end
end

for _, name in ipairs({"progress", "config", "adapter", "ui", "core"}) do
    local path = "tests/" .. name .. ".lua"
    local chunk, err = loadfile(path)
    if not chunk then error(err) end
    chunk()(test, equal)
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
