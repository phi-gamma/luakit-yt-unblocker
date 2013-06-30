#!/usr/bin/env texlua
-----------------------------------------------------------------------
--         FILE:  init.lua
--        USAGE:  require "plugins.yt-unblock"
--  DESCRIPTION:  luakit plugin
-- REQUIREMENTS:  luakit, luafilesystem
--       AUTHOR:  Philipp Gesang (Phg), <phg42.2a@gmail.com>
--      VERSION:  001
--      CREATED:  2013-06-30 16:41:52+0200
-----------------------------------------------------------------------
--

-----------------------------------------------------------------------
-- configuration
-----------------------------------------------------------------------

--- overrides for paths and uris
local env = {
  --prefix      = "/home/phg/.local/share",
  --datapath    = "yt-unblocker",
  --sourceurl   = "http://unblocker.yt",
  --scriptname  = "youtube.js",
}

-----------------------------------------------------------------------
-- imports
-----------------------------------------------------------------------
local lfs   = require "lfs"
local lpeg  = require "lpeg"
local lousy = require "lousy"

local add_cmds      = add_cmds
local info          = info
local load          = load
local unpack        = unpack or table.unpack
local ioopen        = io.open
local iowrite       = io.write
local lfsattributes = lfs.attributes
local setmetatable  = setmetatable
local stringformat  = string.format
local osdate        = os.date

local C, Cf, Cg, Ct, P, R, S
    = lpeg.C, lpeg.Cf, lpeg.Cg, lpeg.Ct, lpeg.P, lpeg.R, lpeg.S
local lpegmatch = lpeg.match

-----------------------------------------------------------------------
-- defaults
-----------------------------------------------------------------------

local defaults = {
  --cachedir    = "cache",
  datapath    = "yt-unblocker",
  prefix      = xdg.data_dir,
  scriptname  = "youtube.js",
  --sourceurl   = "http://unblocker.yt",
}

-----------------------------------------------------------------------
-- main table
-----------------------------------------------------------------------

local yt_unblocker    = { } -- namespace
yt_unblocker.version  = "001"
yt_unblocker.defaults = env
yt_unblocker.defaults = defaults

-----------------------------------------------------------------------
-- helpers
-----------------------------------------------------------------------

local warn = function (...)
  iowrite "unblk>"
  iowrite (stringformat(...))
  iowrite "\n"
end

local isdir = function (path)
  return lfsattributes (path, "mode") == "directory"
end

local isfile = function (name)
  local chan = ioopen (name, "r")
  if chan then
    chan:close()
    return true
  end
  return false
end

local loaddata = function (location)
  local chan = ioopen(location, "r")
  if not chan then
    warn ("cannot open %s for reading", location)
    return false
  end
  local data = chan:read "*all"
  chan:close ()
  return data
end

local readcurrent = function ( )
  local filename = (env.prefix or defaults.prefix)
                .. "/" .. (env.datapath or defaults.datapath)
                .. "/current"
  local chunk = loaddata (filename)
  chunk = load (chunk)
  if not (chunk and type(chunk) == "function") then
    return false
  end
  chunk = chunk ()
  yt_unblocker.scriptversion   = chunk[2]
  yt_unblocker.scripttimestamp = chunk[4]
  return chunk[3]
end

local loadjs = function ( )
  local scriptpath = readcurrent ()
  if not scriptpath or not isfile(scriptpath) then
    return false
  end
  if env.debug == true then
    warn("loading JS from file “%s” (%d bytes)",
         scriptpath, #data)
  end
  return scriptpath, loaddata (scriptpath)
end

-----------------------------------------------------------------------
-- js insertion
-----------------------------------------------------------------------

local scriptcache
local trackstatus = { }

local injectjs = function (view)
  local source, data
  if scriptcache == nil then
    source, data = loadjs ()
    if not source or not data then
      return false
    end
    scriptcache = { source, data }
  else
    source, data = unpack (scriptcache)
  end

  --- doesn’t return anything
  view:eval_js (data, { source    = source,
                        no_return = true, })
  return true
end

local isyt do
  local domain    = P"youtube.com"
  local nodomain  = 1 - domain
  isyt            = nodomain^0 * domain
end

local active = true

local initializer = function (view, w)
  view:add_signal("load-status", function (v, status)
    if active == false then --- disable and return
      trackstatus[v] = false
      return
    end
    if status == "provisional" then
      trackstatus[v] = false
    elseif status == "first-visual" or status == "finished" then
      if lpegmatch (isyt, v.uri) ~= nil and trackstatus[v] ~= true then
        trackstatus[v] = injectjs (v)
      else
        trackstatus[v] = false
      end
    end
  end)
end

webview.init_funcs.yt_unblocker = initializer

-----------------------------------------------------------------------
-- user interface
-----------------------------------------------------------------------

local prefix = "(yt-unblock) "

local infostring = function (...)
  return prefix .. stringformat (...)
end

local cmd = lousy.bind.cmd

local ytcommands = {
  cmd ({ "yt-unblocker-enable", "yt+" }, function (w)
    w:notify (infostring ("start unblocking"))
    active = true
  end),
  cmd ({ "yt-unblocker-disable", "yt-" }, function (w)
    w:notify (infostring ("stop unblocking"))
    active = false
  end),
  cmd ({ "yt-unblocker-status", "ytstat" }, function (w)
    if active == true then
      w:notify (infostring ("unblocking is active"))
    else
      w:notify (infostring ("unblocking is not active"))
    end
  end),
  cmd ({ "yt-unblocker-version", "ytv" }, function (w)
    w:notify
      (infostring ("version %s, script %q, date %s",
                   yt_unblocker.version, yt_unblocker.scriptversion,
                   osdate ("%F %T", yt_unblocker.scripttimestamp)))
  end),
}

add_cmds (ytcommands)

--return yt_unblocker

-- vim:ft=lua:sw=2:ts=2:expandtab:tw=71
