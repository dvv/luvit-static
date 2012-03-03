Fast static server stack layer for Luvit
=====

Usage
-----

```lua
local Stack = require('stack')

local function make_handler()
  return Stack.stack(
    require('static')('/', {
      -- root of static server
      directory = __dirname,
      -- cache in the browser for 1 day
      max_age = 24*60*60*1000,
      -- cache served files
      is_cacheable = function (file_stat)
        -- cache only small files
        -- return file_stat.size < 65536
        -- cache all
        return true
      end,
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
