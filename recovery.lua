-- Downloadable module with recovery tools

local gpu = component.list("gpu", true)()

-- I like copy-pasting the functions
local function invoke(address, method, ...)
  local result = table.pack(pcall(component.invoke, address, method, ...))
  if not result[1] then
    return nil, result[2]
  else
    return table.unpack(result, 2, result.n)
  end
end

-- Colors
local primaryColor = 0x36C436
local background   = 0

-- Some constants
local w, h = invoke(gpu, "getResolution")
local tools = {
  -- TODO: Fix Interpat
  -- {
  --   name = "Interpat by 8urton",
  --   url  = "https://pastebin.com/raw/fsxcwcTY"
  -- },
  {
    name = "UEFI by ECS (press Alt for menu)",
    url  = "https://raw.githubusercontent.com/IgorTimofeev/MineOS/master/EFI/Minified.lua"
  },
  {
    name = "OCBios by titan123023 (press F12 for menu)",
    url  = "https://raw.githubusercontent.com/titan123023/OCBios/master/bios-starter.lua"
  }--,
  -- {
  --   name = "Download OpenOS",
  --   url  = "https://raw.githubusercontent.com/timas130/oc-simple-bios/master/download-openos.lua"
  -- }
}


local drawNext = 6
-- TODO: Make a better way of doing this
local y2url = {}
invoke(gpu, "fill", 1, 6, w, h - 6, " ")
invoke(gpu, "setBackground", primaryColor)
invoke(gpu, "setForeground", background)
for _, i in ipairs(tools) do
  invoke(gpu, "set", 4, drawNext, " " .. i.name .. " ")
  y2url[drawNext] = i.url
  drawNext = drawNext + 2
end

y2url[drawNext] = "exit"
invoke(gpu, "set", 4, drawNext, " EXIT ")

while true do
  local name, _, _, y = computer.pullSignal()
  if name == "touch" then
    local url = y2url[y]
    if not url then
      return
    end
    setStatus("Downloading and running...")
    local result = invoke(component.list("internet", true)(), "request", url).read()
    load(result, "=downloaded.lua", "bt", _G)()
    return
  end
end
