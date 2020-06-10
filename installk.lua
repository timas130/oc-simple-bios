local url = "https://raw.githubusercontent.com/timas130/oc-simple-bios/master/code.min.lua"
local internet = require("component").internet
local eeprom = require("component").eeprom

print("Downloading the code...")
local code = internet.request(url).read()

if not code then
  print("Failed to download the code!")
  os.exit()
end

print("Downloaded, writing BIOS to the EEPROM")
eeprom.set(code)
print("Done, now try rebooting!")
