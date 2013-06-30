#!/usr/bin/env texlua
-----------------------------------------------------------------------
--         FILE:  init.lua
--        USAGE:  require "plugins.yt-unblocker"
--  DESCRIPTION:  luakit plugin
-- REQUIREMENTS:  luakit, luafilesystem
--       AUTHOR:  Philipp Gesang (Phg), <phg42.2a@gmail.com>
--      VERSION:  001
--     MODIFIED:  2013-06-30 23:03:06+0200
-----------------------------------------------------------------------
--

-----------------------------------------------------------------------
-- configuration
-----------------------------------------------------------------------

--- overrides for paths and uris
local env = {
  --prefix      = os.getenv "HOME" .. "/.local/share",
  --datapath    = "yt-unblocker",
  --scriptname  = "youtube.js",
  --configpath  = os.getenv "HOME" .. "/.config/luakit",
  --updater     = "yt-unblock-update.lua",
}

-----------------------------------------------------------------------
-- imports
-----------------------------------------------------------------------
local lfs   = require "lfs"
local lpeg  = require "lpeg"
local lousy = require "lousy"

local add_cmds      = add_cmds
local info          = info
local ioopen        = io.open
local iowrite       = io.write
local lfsattributes = lfs.attributes
local lfscurrentdir = lfs.currentdir
local lfsdir        = lfs.dir
local load          = load
local osdate        = os.date
local osremove      = os.remove
local setmetatable  = setmetatable
local stringfind    = string.find
local stringformat  = string.format
local stringsub     = string.sub
local unpack        = unpack or table.unpack

local C, Cf, Cg, Ct, P, R, S
    = lpeg.C, lpeg.Cf, lpeg.Cg, lpeg.Ct, lpeg.P, lpeg.R, lpeg.S
local lpegmatch = lpeg.match

-----------------------------------------------------------------------
-- defaults
-----------------------------------------------------------------------

local defaults = {
  cachedir    = "cache",
  datapath    = "yt-unblocker",
  prefix      = xdg.data_dir,
  scriptname  = "youtube.js",
  --sourceurl   = "http://unblocker.yt",
  configpath  = luakit.config_dir,
  updater     = "yt-unblock-update.lua",
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

local getpath = function (which)
  local datapath = env.datapath or defaults.datapath
  local prefix   = env.prefix   or defaults.prefix

  if which == "data" then
    return prefix .. "/" .. datapath
  elseif which == "config" then
    return (env.configpath or defaults.configpath)
           .. "/plugins/" .. datapath
--  elseif which == "cache" then
--    return prefix .. "/" .. datapath
--           .. "/" .. (env.cachedir or defaults.cachedir)
  end
end

local stripfirst = function (str)
  local eol = stringfind (str, "\n")
  return stringsub (str, eol + 1)
end

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

--- the rm -r function delivers stats about files and dirs removed

local do_rmrec -- non tail-recursive
do_rmrec = function (start, nd, nf)
  if isdir (start) then
    for ent in lfsdir (start) do
      if ent ~= ".." and ent ~= "." then
        nd, nf = do_rmrec (start .. "/" .. ent, nd, nf)
      end
    end
    osremove (start)
    nd = nd + 1
  elseif isfile (start) then
    osremove (start)
    nf = nf + 1
  end
  return nd, nf
end

local rmrec = function (start)
  return do_rmrec (start, 0, 0)
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
  local filename = getpath "data" .. "/current"
  local chunk = loaddata (filename)
  chunk = load (chunk)
  if not (chunk and type(chunk) == "function") then
    return false
  end
  chunk = chunk ()
  yt_unblocker.scripthash      = chunk[1]
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

local reloadjs = function ()
  scriptcache = nil
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
-- integration with updater
-----------------------------------------------------------------------

--- the updater script can be run independently so there’s quite a
--- bit of duplication wrt functionality; we add the capability to
--- initiate updates here so the user can choose between manual and
--- crontab-based updating.

local update = function ( )
  local filename = getpath "config"
                .. "/" .. (env.updater or defaults.updater)
  if not isfile (filename) then
    return false, "no update script at " .. filename
  end

  local chunk = loaddata (filename)
  chunk = stripfirst (chunk) -- get rid of shebang
  chunk = load (chunk)
  if not chunk or type (chunk) ~= "function" then
    return false, "update script not valid"
  end

  local updater  = chunk ()
  local tupdater = type (updater)
  if tupdater ~= "function" then
    return false, stringformat("expected function, got %s", tupdater)
  end

  local success = updater () == 0
  if not success then
    return false, "update failed"
  end
  return true
end

local cleanupfiles = function ( )
  local kdirs, kfiles = 0, 0
  local rootdir       = getpath "data"
  local cachedir      = (env.cachedir or defaults.cachedir)
  local currentarch   = yt_unblocker.scriptversion
  local currenthash   = yt_unblocker.scripthash
  if not currenthash then
    readcurrent ()
    currenthash = yt_unblocker.scripthash
  end
  for ent in lfsdir (rootdir) do
    local full = rootdir .. "/" .. ent
    if isdir (full) then
      if ent == cachedir then
        for archive in lfsdir (full) do
          if archive ~= currentarch
          and stringsub(archive, 1, 1) ~= "."
          then
            kfiles = kfiles + 1
            orremove(full .. "/" .. archive)
--          else
--            --- current, .., .
          end
        end
      elseif ent ~= currenthash and stringsub (ent, 1, 1) ~= "." then
        local d, f = rmrec (full)
        kdirs, kfiles = kdirs + d, kfiles + f
--      else
--        --- current, .., .
      end
    end
  end
  return kdirs, kfiles
end

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
  cmd ({ "yt-unblocker-reload", "ytr" }, function (w)
    reloadjs ()
    w:notify (infostring ("reloading script (refresh page now)"))
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
      (infostring ("version %s, script %q, downloaded %s",
                   yt_unblocker.version, yt_unblocker.scriptversion,
                   osdate ("%F %T", yt_unblocker.scripttimestamp)))
  end),
  cmd ({ "yt-unblocker-update", "ytu" }, function (w)
    local success, complaint = update ()
    if success == true then
      w:notify (infostring ("update successful"))
    else
      w:notify (infostring ("update failed, reason: %q", complaint))
    end
    collectgarbage "collect"
  end),
  cmd ({ "yt-unblocker-cleanup", "ytc" }, function (w)
    local dirs, files = cleanupfiles ()
    w:notify
      (infostring ("cache empty, removed %d directories and %d files",
                   dirs, files))
  end),
}

add_cmds (ytcommands)

--return yt_unblocker

-- vim:ft=lua:sw=2:ts=2:expandtab:tw=71
