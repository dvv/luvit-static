Fast static server stack layer for Luvit
=====

Usage
-----

```lua
local Static = require('static')

local function makeHandler()
  return require('stack').stack(
    Static(__dirname, {
      -- mountpoint for your static server.
      mount = '/'
      -- cache in the browser for 1 day
      maxAge = 24*60*60*1000,
      -- cache served files
      isCacheable = function (fileStat)
        -- analyze file stat?
        -- return fileStat.size < 65536
        -- or cache all
        return true
      end,
      -- chunk size
      chunkSize = 4096,
      -- follow symlinks
      follow = true,
      -- redirect directories to underneath index.html
      autoIndex = 'README.md',
      -- uncomment to not redirect folders
      -- redirectFolders = false,
    })
  )
end

require('http').createServer(makeHandler()):listen(8080, '0.0.0.0')

print('Static file server listening at http://localhost:8080/')
```

License
-------

[MIT](luvit-static/license.txt)
