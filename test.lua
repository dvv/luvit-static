#!/usr/bin/env luvit

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
        -- cache only small files
        -- return file_stat.size < 65536
        -- cache all
        return true
      end,
      -- follow symlinks
      follow = true,
      -- redirect directories to underneath index.html
      auto_index = 'README.md',
    })
  )
end

require('http').createServer(make_handler()):listen(8080, '0.0.0.0')

print('Static file server listening at http://localhost:8080/')
