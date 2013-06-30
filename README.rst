=======================================================================
                                 what?
=======================================================================

Luakit plugin for managing the `Youtube Unblocker`_.
Injects the script when browsing ``youtube.com``, carries out updates,
and provides user commands for basic control.

=======================================================================
                                 how?
=======================================================================
dependencies
************

In addition to the Luakit_ browser, the unblocker plugin requires the
following libraries:

(#) ``lua-md5``,
(#) ``luafilesystem``,
(#) ``luasocket``, and
(#) the xar_ archiver (not kidding: the unblocker script comes in an
    ``xar`` archive).

At the moment the code runs only with Lua 5.2, so make sure your Luakit
is compiled against that version.
If you haven’t updated yet you can try the `Lua 5.2 branch`_ of my
fork.

install
*******

Clone the `canonical repo`_ from github: ::

    git clone git://github.com/phi-gamma/luakit-yt-unblocker

Now copy the files into a subdirectory of your plugin tree.
With the default settings the plugin expects it to be called
``yt-unblocker``. ::

    targetdir="~/.config/luakit/plugins/yt-unblocker"
    mkdir -p $targetdir
    cp luakit-yt-unblocker/*.lua $targetdir

Now include the main script from your ``rc.lua``: ::

    require "plugins.yt-unblocker"

and launch *Luakit*.
The necessary code from `Youtube Unblocker`_ will be downloaded
during startup.
Youtube censorship should be gone from now on.

usage
*****

All user commands are in the ``yt``-namespace.

    ==========  ========================  =========================
    short       long                      meaning
    ==========  ========================  =========================
    ``yt+``     ``yt-unblocker-enable``   activate plugin
    ``yt-``     ``yt-unblocker-disable``  deactivate plugin
    ``ytstat``  ``yt-unblocker-status``   display activation status
    ``ytr``     ``yt-unblocker-reload``   reload javascript
    ``ytv``     ``yt-unblocker-version``  display version info
    ``ytu``     ``yt-unblocker-update``   update unblocker script
    ``ytc``     ``yt-unblocker-clean``    clean cache directories
    ==========  ========================  =========================

=======================================================================
                              may I ...?
=======================================================================

The plugin is distributed under the terms of the 2-claus BSD license.
See the file ``COPYING`` for details.

=======================================================================
                                 who?
=======================================================================

This plugin was written by `Philipp Gesang`_.
The author is not affiliated with Lunaweb_, the company responsible for
the `Youtube Unblocker`_.

.. _Youtube Unblocker:  http://unblocker.yt
.. _canonical repo:     https://github.com/phi-gamma/luakit-yt-unblocker
.. _Philipp Gesang:     https://www.phi-gamma.net
.. _Lunaweb:            http://www.lunaweb.de
.. _Luakit:             http://luakit.org
.. _xar:                http://code.google.com/p/xar/
.. _Lua 5.2 branch:     https://github.com/phi-gamma/luakit#branch=lua5.2
