--
-- static file server
--

local Table = require('table')
local UV = require('uv_native')
local uv = require('uv')
local Fs = require('fs')
local get_type = require('mime').getType
local date = require('os').date
local resolve = require('path').resolve
local parse_url = require('url').parse

local function noop() end

--
-- open file `path`, seek to `offset` octets from beginning and
-- read `size` subsequent octets.
-- call `progress` on each read chunk
--

local function stream_file(path, offset, size, progress, callback, CHUNK_SIZE)
  CHUNK_SIZE = CHUNK_SIZE or 4096
  UV.fsOpen(path, 'r', '0666', function (err, fd)
    if err then
      callback(err)
      return
    end
    -- FIXME: disk optimization: the very first read() should read data up to
    -- the start of next CHUNK_SIZE, so that subsequent reads be aligned?
    local readchunk
    readchunk = function ()
      local chunk_size = size < CHUNK_SIZE and size or CHUNK_SIZE
      UV.fsRead(fd, offset, chunk_size, function (err, chunk)
        if err or #chunk == 0 then
          callback(err)
          UV.fsClose(fd, noop)
        else
          chunk_size = #chunk
          offset = offset + chunk_size
          size = size - chunk_size
          if progress then
            progress(chunk, readchunk)
          else
            readchunk()
          end
        end
      end)
    end
    readchunk()
  end)
end

--
-- setup request handler
--

local function static_handler(mount, options)
  if not options then options = { } end

  -- given Range: header, return start, end numeric pair
  local function parse_range(range, size)
    local partial, start, stop = false
    -- parse bytes=start-stop
    if range then
      start, stop = range:match('bytes=(%d*)-?(%d*)')
      partial = true
    end
    start = tonumber(start) or 0
    stop = tonumber(stop) or size - 1
    return start, stop, partial
  end

  -- cache entries table
  local cache = { }
  -- handler for 'change' event of all file watchers
  local function invalidate_cache_entry(status, event, path)
    -- invalidate cache entry and free the watcher
    if cache[path] then
      local entry = cache[path]
      cache[path] = nil
      entry.watch:close()
      entry.watch = nil
    end
  end

  -- given file, serve contents, honor Range: header
  local function serve(self, file, range, cache_it)
    -- adjust headers
    local headers = { }
    for k, v in pairs(file.headers) do headers[k] = v end
    local size = file.size
    local start = 0
    local stop = size - 1
    -- range specified? adjust headers and http status for response
    if range then
      -- limit range by file size
      start, stop = parse_range(range, size)
      -- check range validity
      if stop >= size then
        stop = size - 1
      end
      if stop < start then
        self:writeHead(416, {
          ['Content-Range'] = 'bytes=*/' .. file.size
        })
        self:finish()
        return
      end
      -- adjust Content-Length:
      headers['Content-Length'] = stop - start + 1
      -- append Content-Range:
      headers['Content-Range'] = ('bytes=%d-%d/%d'):format(start, stop, size)
      self:writeHead(206, headers)
    else
      self:writeHead(200, headers)
    end
    -- serve from cache, if available
    if file.data then
      self:finish(
          range and file.data.sub(start + 1, stop - start + 1) or file.data
        )
    -- otherwise stream and possibly cache
    else
      -- N.B. don't cache if range specified
      if range then
        cache_it = false
      end
      local index, parts = 1, { }
      -- called when file chunk is served
      local function progress(chunk, cb)
        if cache_it then
          parts[index] = chunk
          index = index + 1
        end
        self:write(chunk, cb)
      end
      -- called when file is served
      local function eof(err)
        self:finish()
        if cache_it then
          file.data = Table.concat(parts, '')
        end
      end
      stream_file(
          file.name,
          start,
          stop - start + 1,
          progress,
          eof,
          options.chunk_size
        )
    end
  end

  -- cache some locals
  local fstat = options.follow and Fs.stat or Fs.lstat
  local max_age = options.max_age or 0
  local uri_skip = #mount + 1
  local auto_index = options.auto_index

  --
  -- request handler
  --
  return function (req, res, nxt)

    -- none of our business unless method is GET
    -- or uri doesn't start with `mount`
    local uri = req.uri or parse_url(req.url)
    if req.method ~= 'GET' or uri.pathname:find(mount, 1, true) ~= 1 then
      nxt()
      return
    end

    -- map url to local filesystem filename
    -- TODO: Path.normalize(req.url)
    local filename = resolve(options.directory, uri.pathname:sub(uri_skip))

    -- filename ends with / and auto_index allowed?
    if auto_index and filename:sub(-1, -1) == '/' then
      -- append auto_index to filename
      filename = filename .. auto_index
    end

    -- stream file, possibly caching the contents for later reuse
    local file = cache[filename]
    -- no need to serve anything if file is cached at client side
    if file
      and file.headers['Last-Modified'] == req.headers['if-modified-since']
    then
      res:writeHead(304, file.headers)
      res:finish()
      return
    end

    if file then
      serve(res, file, req.headers.range, false)
    else
      fstat(filename, function (err, stat)
        -- filename not found? proceed to next layer
        if err then nxt() ; return end
        -- filename is directory? proceed to next layer
        -- FIXME: filename = Path.join(filename, auto_index)?
        if stat.is_directory then nxt() ; return end
        -- create cache entry, even for files which contents are not
        -- gonna be cached
        -- collect information on file
        file = {
          name = filename,
          size = stat.size,
          mtime = stat.mtime,
          -- FIXME: finer control client-side caching
          headers = {
            ['Content-Type'] = get_type(filename),
            ['Content-Length'] = stat.size,
            ['Cache-Control'] = 'public, max-age=' .. (max_age / 1000),
            ['Last-Modified'] = date('!%c', stat.mtime),
            ['Etag'] = stat.size .. '-' .. stat.mtime
          },
        }
        -- allocate cache entry
        cache[filename] = file
        -- should any changes in this file occur, invalidate cache entry
        -- TODO: reuse caching technique from luvit/kernel
        file.watch = uv.Watcher:new(filename)
        file.watch:setHandler('change', invalidate_cache_entry)
        -- shall we cache file contents?
        local cache_it = options.is_cacheable and options.is_cacheable(file)
        serve(res, file, req.headers.range, cache_it)
      end)
    end
  end
end

-- module
return static_handler
