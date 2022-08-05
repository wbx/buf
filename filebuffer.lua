--->use-luvit<---

local fs = require 'fs'
local bit = require 'bit'
local ffi = require 'ffi'

ffi.cdef [[
    //void* malloc(size_t size);
    //void free(void* mem);
    //void* memset(void* ptr, int val, size_t n);

    typedef struct _FILE FILE;

    FILE *fopen(const char *filename, const char *mode);
    int setvbuf(FILE *stream, char *buf, int mode, size_t size);
    int fflush(FILE *stream);

    size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);

    int fgetc(FILE *stream);
    int fputc(int ch, FILE *stream);
    int fputs(const char *string, FILE *stream);

    int fclose(FILE *stream);
]]

if ffi.abi('64bit') then
    if ffi.abi('win') then
        ffi.cdef [[
            int fseek(FILE *stream, int64_t offset, int whence) __asm__("_fseeki64");
            int64_t ftell(FILE *stream) __asm__("_ftelli64");
        ]]
    else
        ffi.cdef [[
            int fseek(FILE *stream, int64_t offset, int whence) __asm__("fseeko64");
            int64_t ftell(FILE *stream) __asm__("ftello64");
        ]]
    end
else
    ffi.cdef [[
        int fseek(FILE *stream, long offset, int whence);
        long ftell(FILE *stream);
    ]]
end

local SEEK = {
    SET = 0,
    CUR = 1,
    END = 2,
}


-- local C = (ffi.os == 'Windows') and ffi.load('msvcrt') or ffi.C
local U = (ffi.os == 'Windows') and ffi.load('ucrtbase') or ffi.C

---@alias endianness
---|>'"le"' # Little-endian
---| '"be"' # Big-endian

--- File buffer for sequential and 0-indexed reading/writing.
---@class FileBuffer
---@field pos number    # Position to read next
---@field mode endianness # Endianness of buffer reads/writes
---@field rw boolean    # Is the buffer also writable
---@field pos_stack number[] # Position stack for push and pop operations
---@field file ffi.cdata* # File handle
---@field _funcs table private
local FileBuffer = {}

---@class FileBuffer
local LEfn = {}

---@class FileBuffer
local BEfn = {}


local function FileBuffer__index(self, key)
    if type(key) == 'number' then
        assert(key >= 0, "Index cannot be negative.")
        self:push():seek(key)
        local b = U.fgetc(self.file)
        self:pop()
        assert(b ~= -1, "Reached end of file.")

        return b
    end
    if key == 'pos' then
        return U.ftell(self.file)
    end
    return self._funcs[key] or FileBuffer[key]
end


---@return FileBuffer?, string?
function FileBuffer.from(filename, options)
    options = options or {}

    local self = setmetatable({}, {__index = FileBuffer__index})
    self.mode = options.mode == 'be' and 'be' or 'le'
    self.rw = options.rw and true or false
    self.pos_stack = {}
    self.bufsize = options.bufsize or 0
    self._funcs = (self.mode == 'be') and BEfn or LEfn

    -- Since we can't somehow get errno, use uv fs to get error if any
    do
        local fd, errn, errmsg = fs.openSync(filename, self.rw and 'r+' or 'r')
        if not fd then
            return nil, errn .. ": " .. errmsg
        end
        fs.closeSync(fd)
    end

    self.file = U.fopen(filename, self.rw and 'rb+' or 'rb')
    if self.file == nil then
        return nil, "Unknown error."
    end

    ffi.gc(self.file, U.fclose)

    if self.bufsize > 0 then
        -- Buffer with specified size
        U.setvbuf(self.file, nil, 0, self.bufsize)
    elseif self.bufsize < 0 then
        -- No buffer
        U.setvbuf(self.file, nil, 4, 0)
    end

    return self
end


--- Other ---

function FileBuffer:checkWrite()
    assert(self.rw, "Buffer is read-only, write operations not supported.")
    -- needed due to buffering
    U.fseek(self.file, 0, SEEK.CUR)
end

function FileBuffer:flush()
    U.fflush(self.file)
end

function FileBuffer:close()
    U.fclose(ffi.gc(self.file, nil))
    setmetatable(self, {__index = function() error("FileBuffer already closed.") end})
end


--- Position functions ---

--- Advance pos by `n`, returning current position before advance
function FileBuffer:advance(n)
    local current = self.pos
    U.fseek(self.file, n, SEEK.CUR)
    return current
end

function FileBuffer:push()
    table.insert(self.pos_stack, self.pos)
    return self
end

function FileBuffer:pop()
    local n = assert(table.remove(self.pos_stack), "Nothing to pop from position stack.")
    U.fseek(self.file, n, SEEK.SET)
    return self
end

---@param pos number
function FileBuffer:seek(pos)
    assert(type(pos) == 'number' or type(pos) == 'cdata', "pos must be a number.")
    U.fseek(self.file, pos, pos < 0 and SEEK.END or SEEK.SET)
    return self
end


--- Read functions ---

local function complement8(n)
    return (n < 0x80) and n or (n - 0x100)
end

local function complement16(n)
    return (n < 0x8000) and n or (n - 0x10000)
end

local function complement32(n)
    return bit.band(n, 0x80000000) == 0 and (n)
        or (n - 0xffffffff - 1)
end

--

function LEfn:read_u8()
    local b = U.fgetc(self.file)
    assert(b ~= -1, "Reached end of file.")

    return b
end
BEfn.read_u8 = LEfn.read_u8

function LEfn:read_i8()
    return complement8(self:read_u8())
end
BEfn.read_i8 = LEfn.read_i8

--

function LEfn:read_u16()
    local buf = ffi.new("uint8_t[2]")
    local br = U.fread(buf, 1, 2, self.file)
    if br < 2 then
        self:advance(-br)
        error("Reached end of file.")
    end

    return buf[0] +
        bit.lshift(buf[1], 8)
end
function BEfn:read_u16()
    local buf = ffi.new("uint8_t[2]")
    local br = U.fread(buf, 1, 2, self.file)
    if br < 2 then
        self:advance(-br)
        error("Reached end of file.")
    end

    return bit.lshift(buf[0], 8) +
        buf[1]
end

function LEfn:read_i16()
    return complement16(self:read_u16())
end
BEfn.read_i16 = LEfn.read_i16

--

function LEfn:read_u32()
    local buf = ffi.new("uint8_t[4]")
    local br = U.fread(buf, 1, 4, self.file)
    if br < 4 then
        self:advance(-br)
        error("Reached end of file.")
    end

    return buf[0] +
        bit.lshift(buf[1], 8) +
        bit.lshift(buf[2], 16) +
        0x1000000* buf[3]           -- lshift(x, 24)
end
function BEfn:read_u32()
    local buf = ffi.new("uint8_t[4]")
    local br = U.fread(buf, 1, 4, self.file)
    if br < 4 then
        self:advance(-br)
        error("Reached end of file.")
    end

    return 0x1000000 * buf[0] +     -- lshift(x, 24)
        bit.lshift(buf[1], 16) +
        bit.lshift(buf[2], 8) +
        buf[3]
end

function LEfn:read_i32()
    return complement32(self:read_u32())
end
BEfn.read_i32 = LEfn.read_i32

--

function FileBuffer:read_bytes(len)
    assert(type(len) == 'number' and len >= 0, "len must be a positive integer.")

    local buf = ffi.new("char[?]", len)
    assert(U.fread(buf, 1, len, self.file) == len, "Reached end of file.")

    return ffi.string(buf, len)
end


--- Write functions ---

function LEfn:write_u8(val)
    self:checkWrite()
    assert(U.fputc(val, self.file) ~= -1, "Reached end of file.")

    return self
end
BEfn.write_u8 = LEfn.write_u8
LEfn.write_i8 = LEfn.write_u8
BEfn.write_i8 = LEfn.write_u8

--

function LEfn:write_u16(val)
    self:checkWrite()
    assert(U.fputc(val, self.file) ~= -1, "Reached end of file.")
    assert(U.fputc(bit.rshift(val, 8), self.file) ~= -1, "Reached end of file.")

    return self
end
LEfn.write_i16 = LEfn.write_u16

function BEfn:write_u16(val)
    self:checkWrite()
    assert(U.fputc(bit.rshift(val, 8), self.file) ~= -1, "Reached end of file.")
    assert(U.fputc(val, self.file) ~= -1, "Reached end of file.")

    return self
end
BEfn.write_i16 = BEfn.write_u16

--

function LEfn:write_u32(val)
    self:checkWrite()
    assert(U.fputc(bit.band(val, 0xff), self.file) ~= -1, "Reached end of file.")
    assert(U.fputc(bit.rshift(val, 8), self.file) ~= -1, "Reached end of file.")
    assert(U.fputc(bit.rshift(val, 16), self.file) ~= -1, "Reached end of file.")
    assert(U.fputc(bit.rshift(val, 24), self.file) ~= -1, "Reached end of file.")

    return self
end
LEfn.write_i32 = LEfn.write_u32

function BEfn:write_u32(val)
    self:checkWrite()
    assert(U.fputc(bit.rshift(val, 24), self.file) ~= -1, "Reached end of file.")
    assert(U.fputc(bit.rshift(val, 16), self.file) ~= -1, "Reached end of file.")
    assert(U.fputc(bit.rshift(val, 8), self.file) ~= -1, "Reached end of file.")
    assert(U.fputc(bit.band(val, 0xff), self.file) ~= -1, "Reached end of file.")

    return self
end
BEfn.write_i32 = BEfn.write_u32

--

function FileBuffer:write_bytes(val)
    self:checkWrite()
    assert(U.fputs(val, self.file) ~= -1, "Reached end of file.")
    return self
end


return FileBuffer