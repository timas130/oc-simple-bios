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

local floor = math.floor
local gpu, screen = component.list("gpu", true)(), component.list("screen", true)()

-- Shamelessly copied from OpenOS ¯\_(ツ)_/¯
function sleep(timeout)
  local deadline = computer.uptime() + (timeout or 0)
  repeat
    computer.pullSignal(deadline - computer.uptime())
  until computer.uptime() >= deadline
end

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

-- Drawing welcome/title text at the top of the screen
local welcomeMessage = "Simple BIOS 1.0"
invoke(gpu, "set", floor(w / 2 - #welcomeMessage / 2), 3, welcomeMessage)

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
    local label = string.len(invoke(i, "getLabel"))
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

    invoke(gpu, "set", w - string.len(renameText) - 1, drawNext, renameText)

    y2drive[drawNext] = i

    drawNext = drawNext + 2

    ::dskip::
  end
end

local renameInput = false
local renameAddress = ""
local renameLabel = ""
local renameMessage = "New name, empty to reset: "
function renameDrive(address)
  invoke(gpu, "setBackground", background)
  invoke(gpu, "setForeground", primaryColor)
  invoke(gpu, "fill", 4, h - 2, w - 4, 1, " ")
  invoke(gpu, "set", 4, h - 2, renameMessage)
  renameAddress = address
  renameInput = true
  renameLabel = ""
end

drawDrives()

local deadline = computer.uptime() + 5
while true do
  local name, c, x, y = computer.pullSignal(deadline - computer.uptime())
  if name == "key_down" and renameInput then
    if y == 0x0E then -- Backspace
      renameLabel = renameLabel:sub(1, -2)
      invoke(gpu, "fill", 4, h - 2, w - 4, 1, " ")
      invoke(gpu, "set", 4, h - 2, renameMessage .. renameLabel)
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
      renameLabel = renameLabel .. string.char(x)
      invoke(gpu, "fill", 4, h - 2, w - 4, 1, " ")
      invoke(gpu, "set", 4, h - 2, renameMessage .. renameLabel)
    end
  elseif name == "touch" then
    deadline = math.huge
    local d = y2drive[y]
    if not d then
      goto skip
    end

    if x >= w - string.len(renameText) - 1 then
      renameDrive(d)
      goto skip
    end

    if invoke(d, "exists", "init.lua") then
      invoke(gpu, "fill", 4, h - 2, w - 4, 1, " ")
      invoke(gpu, "set", 4, h - 2, "Loading from this device...")
      boot(d)
    else
      invoke(gpu, "fill", 4, h - 2, w - 4, 1, " ")
      invoke(gpu, "set", 4, h - 2, "This device is not loadable, init.lua missing!")
    end
  end
  if computer.uptime() >= deadline then
    -- Booting into default drive
    boot(computer.getBootAddress())
  end
  ::skip::
end
