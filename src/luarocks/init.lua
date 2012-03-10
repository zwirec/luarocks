
local luarocks = {}

local cfg = require("luarocks.cfg")

function luarocks.new(program_name, program_description, commands)
   local lr = {
      version = cfg.program_version,
      program_name = program_name or "luarocks-api",
      program_description = program_description or "LuaRocks programmatical interface",
      commands = commands or {},
   }
   local lr_mt = {
      __index = function(t, k)
         if type(k) == "string" and k:match("^[a-z_]+$") then
            local ok, mod = pcall(require, "luarocks."..k)
            if ok and mod and mod.run then
               local fn = function(...) return mod.run(...) end
               rawset(t, k, fn)
               return fn
            end
         end
      end
   }
   setmetatable(lr, lr_mt)
   return lr
end

return luarocks
