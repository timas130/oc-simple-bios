-- Shamelessly copied from original bootloader
local component_invoke = component.invoke
local function invoke(address, method, ...)
  local result = table.pack(pcall(component_invoke, address, method, ...))
  if not result[1] then
    return nil, result[2]
  else
    return table.unpack(result, 2, result.n)
  end
end

function waitForCtrl(timeout)
  local deadline = computer.uptime() + timeout
  repeat
    local name, _, _, code = computer.pullSignal(deadline - computer.uptime())
    -- Right Ctrl or Left Ctrl \
    if name == "key_down" and (code == 0x1D or code == 0x9D) then
      return true
    end
  until computer.uptime() >= deadline
  return false
end

local floor = math.floor
local gpu, screen = component.list("gpu", true)(), component.list("screen", true)()

-- For compatibility
local eeprom = component.list("eeprom", true)()
computer.getBootAddress = function()
  return invoke(eeprom, "getData")
end
computer.setBootAddress = function(address)
  return invoke(eeprom, "setData", address)
end

function boot(d)
  local handle = invoke(d, "open", "init.lua", "r")
  local buffer = ""
  repeat
    local data = invoke(d, "read", handle, math.huge)
    buffer = buffer .. (data or "")
  until not data
  invoke(d, "close", handle)
  local status, value = pcall(load(buffer, "=init", "bt", _G))
  invoke(gpu, "fill", 1, 1, w, h, " ")
  invoke(gpu, "setBackground", 0x000000)
  if not status then
    invoke(gpu, "setForeground", 0xFF0000)
    invoke(gpu, "set", 1, 1, value)
    while true do -- Time to see the error
      computer.pullSignal()
    end
  else
    invoke(gpu, "setForeground", 0x00FF00)
    invoke(gpu, "set", 1, 1, "Program completed.")
  end
end

-- Colors
local primaryColor = 0x36C436
local background   = 0

-- Standart screen resetting work
invoke(gpu, "bind", screen)
local w, h = invoke(gpu, "maxResolution")
invoke(gpu, "setResolution", w, h)
invoke(gpu, "setForeground", primaryColor)
invoke(gpu, "setBackground", background)
invoke(gpu, "fill", 1, 1, w, h, " ")
local pressCtrl = "Press Ctrl to enter boot menu"
invoke(gpu, "set", floor(w / 2 - unicode.len(pressCtrl) / 2), 4, pressCtrl)

if not waitForCtrl(1) then
  boot(computer.getBootAddress())
else
  invoke(gpu, "fill", 1, 1, w, h, " ")
end

function setStatus(msg)
  invoke(gpu, "fill", 4, h - 2, w - 4, 1, " ")
  invoke(gpu, "set", 4, h - 2, msg)
end

-- Drawing welcome/title text at the top of the screen
local welcomeMessage = "Simple BIOS 1.1"
invoke(gpu, "set", floor(w / 2 - unicode.len(welcomeMessage) / 2), 3, welcomeMessage)

local drives
local maxLabel = nil
local y2drive = {}

local renameText = "RENAME"
function drawDrives()
  invoke(gpu, "setBackground", background)
  invoke(gpu, "setForeground", primaryColor)
  invoke(gpu, "fill", 1, 4, w, h - 4, " ")

  drives = component.list("filesystem", true)
  for i in drives do
    local label = unicode.len(invoke(i, "getLabel"))
    if not maxLabel or label > maxLabel then
      maxLabel = label
    end
  end

  local drawNext = 6
  for i in drives do
    if not invoke(i, "exists", "init.lua") then
      goto dskip
    end
    invoke(gpu, "setBackground", primaryColor)
    invoke(gpu, "setForeground", background)
    local label = invoke(i, "getLabel")
    invoke(gpu, "set", 4, drawNext, " " .. label .. " ")

    invoke(gpu, "setBackground", background)
    invoke(gpu, "setForeground", primaryColor)

    if i == computer.getBootAddress() then
      invoke(gpu, "set", maxLabel + 8, drawNext, "Default device")
    elseif not invoke(i, "exists", "init.lua") then
      invoke(gpu, "set", maxLabel + 8, drawNext, "Not loadable")
    elseif invoke(i, "isReadOnly") then
      invoke(gpu, "set", maxLabel + 8, drawNext, "Read-only, loadable")
    else
      invoke(gpu, "set", maxLabel + 8, drawNext, "Loadable")
    end

    invoke(gpu, "set", w - unicode.len(renameText) - 1, drawNext, renameText)

    y2drive[drawNext] = i

    drawNext = drawNext + 2

    ::dskip::
  end

  drawNext = drawNext + 1

  if component.list("internet", true)() then
    invoke(gpu, "set", 4, drawNext, " Download recovery tools ")
    y2drive[drawNext] = "internet"
  end
end

local renameInput = false
local renameAddress = ""
local renameLabel = ""
local renameMessage = "New name, empty to reset: "
function renameDrive(address)
  invoke(gpu, "setBackground", background)
  invoke(gpu, "setForeground", primaryColor)
  setStatus(renameMessage)
  renameAddress = address
  renameInput = true
  renameLabel = ""
end

drawDrives()

while true do
  local name,c,x,y = computer.pullSignal()
  if name == "key_down" and renameInput then
    if y == 0x0E then -- Backspace
      renameLabel = unicode.sub(renameLabel, 1, -2)
      setStatus(renameMessage .. renameLabel)
    elseif y == 0x1C then -- Enter
      renameInput = false
      if string.len(renameLabel) == 0 then
        invoke(gpu, "fill", 4, h - 2, w - 4, 1, " ")
        drawDrives()
        goto skip
      end
      invoke(renameAddress, "setLabel", renameLabel)
      invoke(gpu, "fill", 4, h - 2, w - 4, 1, " ")
      drawDrives()
    elseif string.len(renameLabel) < 16 and x ~= 0 then
      renameLabel = renameLabel .. unicode.char(x)
      setStatus(renameMessage .. renameLabel)
    end
  elseif name == "touch" then
    deadline = math.huge
    local d = y2drive[y]
    if not d then
      goto skip
    end

    if d == "internet" then
      setStatus("Downloading recovery module...")
      -- TODO: Change localhost URL
      local result = invoke(component.list("internet", true)(), "request", "https://raw.githubusercontent.com/timas130/oc-simple-bios/master/recovery.lua").read()
      -- if not reuslt then
      --   setStatus("Failed to download recovery tools, check the connection?")
      --   goto skip
      -- end
      load(result, "=recovery.lua", "bt", _G)()
      waitForCtrl(5)
      drawDrives()
      goto skip
    end

    if x >= w - string.len(renameText) - 1 then
      renameDrive(d)
      goto skip
    end

    if invoke(d, "exists", "init.lua") then
      setStatus("Loading from this device...")
      boot(d)
    else
      setStatus("This device is not loadable, init.lua missing!")
    end
  end
  ::skip::
end
