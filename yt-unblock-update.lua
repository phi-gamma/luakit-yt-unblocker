#!/usr/bin/env texlua
-----------------------------------------------------------------------
--         FILE:  yt-unblock-update.lua
--        USAGE:  with crontab
--  DESCRIPTION:  update the yt-unblocker source for luakit
-- REQUIREMENTS:  lua 5.2, lua-md5, luafilesystem, lpeg, luasocket, xar
--       AUTHOR:  Philipp Gesang (Phg), <phg42.2a@gmail.com>
--      VERSION:  1.0
--      CREATED:  2013-06-29 16:05:39+0200
-----------------------------------------------------------------------
--
--- this script requires the “xar” decompression tool to be present
--- https://aur.archlinux.org/packages/xar/

-----------------------------------------------------------------------
-- config
-----------------------------------------------------------------------

--- overrides for paths and uris
local env = {
  --prefix      = "/home/phg/.local/share",
  --datapath    = "yt-unblocker",
  --sourceurl   = "http://unblocker.yt",
  --scriptname  = "youtube.js",
}

print "update running"

-----------------------------------------------------------------------
-- imports
-----------------------------------------------------------------------

local http = require "socket.http"
local lfs  = require "lfs"
local lpeg = require "lpeg"
local md5  = require "md5"

local ioopen        = io.open
local iowrite       = io.write
local lfsattributes = lfs.attributes
local lfschdir      = lfs.chdir
local lfscurrentdir = lfs.currentdir
local lfsdir        = lfs.dir
local lfsmkdir      = lfs.mkdir
local osexecute     = os.execute
local osgetenv      = os.getenv
local ostime        = os.time
local stringfind    = string.find
local stringformat  = string.format
local stringgmatch  = string.gmatch
local stringmatch   = string.match

local C, Cf, Cg, Ct, P, R, S
    = lpeg.C, lpeg.Cf, lpeg.Cg, lpeg.Ct, lpeg.P, lpeg.R, lpeg.S
local lpegmatch = lpeg.match

-----------------------------------------------------------------------
-- defaults
-----------------------------------------------------------------------

--- default according to http://standards.freedesktop.org/basedir-spec/basedir-spec-latest.html#variables
local defaults = {
  cachedir    = "cache",
  datapath    = "yt-unblocker",
  prefix      = ".local/share",
  scriptname  = "youtube.js",
  sourceurl   = "http://unblocker.yt",
}

-----------------------------------------------------------------------
-- helpers
-----------------------------------------------------------------------

local complain = function (...)
  iowrite "!> "
  iowrite(stringformat(...))
  iowrite "\n"
end

local abort = function (...)
  if select ("#", ...) > 0 then
    complain (...)
  end
  os.exit (1)
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

local mkdirs = function (path)
  local full = ""
  for component in stringgmatch (path, "(/*[^\\/]+)") do 
    full = full .. component
    lfsmkdir (full)
  end
end

local firstpath = function (paths)
  local first = stringmatch (paths, "^:*([^:]+)")
  return first
end

local basename
do
  local slash   = P"/"
  local noslash = 1 - slash
  local eos     = P(-1)
  local p_base  = (noslash^0 * slash^1)^1 * C(noslash^1) * eos
  basename = function (name)
    return lpegmatch (p_base, name)
  end
end

local getdatapath = function ( )
  local datadir = env.prefix
  if not datadir then
    datadir = osgetenv "XDG_DATA_HOME"
  end
  if not datadir then
    datadir = osgetenv "HOME" .. "/" .. defaults.prefix
  end
  datadir = datadir .. "/" .. (env.datapath or defaults.datapath)
  if not isdir (datadir) then
    mkdirs (datadir)
    if not isdir (datadir) then
      abort("cannot create directory %s, aborting.", datadir)
    end
  end
  return datadir
end

local getcachepath = function (root)
  local path = root .. "/" .. (env.cachedir or defaults.cachedir)
  if not isdir (path) then
    mkdirs (path)
  end
  return path
end

local retrievepage = function (url)
  local struff = assert(http.request (url),
                        "could not access %s" .. url)
  return struff
end

local savedata = function (location, data)
  local chan = ioopen(location, "w")
  if not chan then
    abort ("cannot open %s for writing", location)
  end
  chan:write(data)
  chan:close()
end

local loaddata = function (location)
  local chan = ioopen(location, "r")
  if not chan then
    abort ("cannot open %s for reading", location)
  end
  local data = chan:read "*all"
  chan:close ()
  return data
end

local xar_extract
do
  local chan = io.popen ("which xar", "r")
  local xar_cmd = chan:read "*line"
  chan:close()
  if not xar_cmd then
    abort "cannot find xar utility"
  end

  --- that thing’s a bit daft; cannot be piped to, won’t
  --- write to pipe -- but it comes with an xml index …‽
  ---
  --- there appears to be a fork at http://mackyle.github.io/xar/
  --- that comes with basic directory support but since it’s
  --- not the one in the AUR we can’t rely on it

  local xar_cmd = xar_cmd .. " -xf %s"

  xar_extract = function (filename, target)
    local cwd = lfscurrentdir ()
    lfschdir (target)
    local s, t, r = osexecute (stringformat(xar_cmd, filename))
    if s ~= true or t ~= "exit" or r ~= 0 then
      lfschdir (cwd)
      abort ("failed to extract %s", filename)
    end

    local extpath
    local curdir = lfscurrentdir ()
    local scriptname = (env.scriptname or defaults.scriptname)
    for ent in lfsdir (curdir) do
      if lfsattributes (ent, "mode") == "directory" then
        local p = curdir .. "/" .. ent .. "/" .. scriptname
        if lfsattributes (p, "mode") == "file" then
          extpath = p
          break
        end
      end
    end
    lfschdir (cwd)
    if extpath == nil then
      abort ("cannot locate script file (%s) in archive", scriptname)
    end
    return extpath
  end
end

-----------------------------------------------------------------------
-- grab the archive uri
-----------------------------------------------------------------------

local extracturi
do
  local spacechar     = S" \t\v\n\r"
  local optws         = spacechar^0
  local equals        = P"="
  local dquote        = P[["]]
  local abra, aket    = P"<", P">"
  local noaket        = (1 - aket)
  local bdiv          = P"<div"
  local ediv          = P"</div>"
  local idcontent     = P[[id="content"]]
  local bcontent      = bdiv * spacechar
                      * (1 - idcontent - aket)^0 * idcontent
                      * noaket^0 * aket
  local bentry        = P"<div" * noaket^0 * aket * optws
  local eentry        = ediv * optws
  local head          = P"<h2>" * C((1 - P"</h2>")^0) * P"</h2>" * optws
  local bpar          = P"<p>"
  local epar          = P"</p>"
  local noepar        = (1 - epar)^0
  local namestart     = R("az", "AZ") + S":_"
  local namechar      = namestart + P"-" + P"." + R"09"
  local name          = namestart * namechar^0
  local lhs           = C(name^1)
  local rhs           = dquote * C((1 - dquote)^1) * dquote
  local attribute     = Cg(lhs * equals * rhs)
  local attributes    = Cf(Ct"" * attribute
                           * (spacechar * optws * attribute)^0,
                           rawset)
  local banchor       = P"<a" * spacechar * attributes * optws * aket
  local eanchor       = P"</a>"
  local link          = banchor * (1 - eanchor)^0 * eanchor
  local par           = bpar
                      * optws
                      * (1 - epar - link)^0
                      * link
                      * noepar
                      * epar
                      * optws
  local entry         = (1 - bentry)^0 -- skip crap
                      * bentry
                      * Ct(Cg(head, "name") * Cg(par, "data"))
                      * eentry
  local junk          = (1 - bcontent)^0 * bcontent * optws
  local p_entries     = junk * Ct(entry^1)

  extracturi = function (rawhtml)
    local entries = lpegmatch(p_entries, rawhtml)
    if entries then
      for i=1, #entries do
        local entry = entries[i]
        local data  = entry.data
        if data then
          if stringfind(entry.name, "^Safari") then
            return entry.data.href
          end
        end
      end
    end
    abort "could not extract URI’s, unblocker plugin might be outdated"
  end
end

-----------------------------------------------------------------------
-- download and extract the archive
-----------------------------------------------------------------------

local write_current = function (path, chksum, name, scriptfile)
  local location = path .. "/current"
  local content  = stringformat
    ("return {\n  %q,\n  %q,\n  %q,\n  %q,\n}\n",
     chksum, name, scriptfile, ostime ())
  savedata (location, content)
end

local retrievearch = function (datapath, uri)
  local datapath  = getdatapath ()
  local cachepath = getcachepath (datapath)
  local filename  = basename (uri)
  local filepath  = cachepath .. "/" .. filename

  local data

  --- download only if not in cache
  if not isfile (filepath) then
    local bin, errmsg = http.request (uri)
    if not bin then
      abort ("download from %s failed, reason: %s", uri, errmsg)
    end
    savedata (filepath, bin)
    data = bin
  else
    data = loaddata (filepath)
  end

  local chksum    = md5.sumhexa (data) -- also dirname
  local targetdir = datapath .. "/" .. chksum
  if not isdir (targetdir) then
    mkdirs (targetdir)
  end

  local scriptfile = xar_extract (filepath, targetdir)
  write_current (datapath, chksum, filename, scriptfile)
end

-----------------------------------------------------------------------
-- updater
-----------------------------------------------------------------------

local update = function ( )
  local sourceurl = env.sourceurl or defaults.sourceurl
  local rawdata   = retrievepage (sourceurl)
  local uri       = sourceurl .. "/" .. extracturi (rawdata)
  local archfile  = retrievearch (datapath, uri)
  return 0
end

return update ()

