Fast static server stack layer for Luvit
=====

Usage
-----

```lua
local Static = require('static')

local function make_handler()
  return require('stack').stack(
    Static('/', {
      -- root of static server
      directory = __dirname,
      -- cache in the browser for 1 day
      max_age = 24*60*60*1000,
      -- cache served files
      is_cacheable = function (file_stat)
        -- analyze file stat?
        -- return file_stat.size < 65536
        -- or cache all
        return true
      end,
      -- chunk size
      chunk_size = 4096,
      -- follow symlinks
      follow = true,
      -- redirect directories to underneath index.html
      auto_index = 'index.html',
    })
  )
end

require('http').createServer(make_handler()):listen(8080, '0.0.0.0')

print('Static file server listening at http://localhost:8080/')
```

License
-------

[MIT](luvit-static/license.txt)
