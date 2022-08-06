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
    size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);

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


if ffi.abi('win') then
    ffi.cdef [[
        uint16_t bswap16(uint16_t x) __asm__("_byteswap_ushort");
        uint32_t bswap32(uint32_t x) __asm__("_byteswap_ulong");
        uint64_t bswap64(uint64_t x) __asm__("_byteswap_uint64");
    ]]
else
    ffi.cdef [[
        uint16_t bswap16(uint16_t x) __asm__("__builtin_bswap16");
        uint32_t bswap32(uint32_t x) __asm__("__builtin_bswap32");
        uint64_t bswap64(uint64_t x) __asm__("__builtin_bswap64");
    ]]
end

ffi.cdef [[
    union arrToU16 { uint8_t arr[2]; uint16_t n; };
    union arrToU32 { uint8_t arr[4]; uint32_t n; };
    union arrToU64 { uint8_t arr[8]; uint64_t n; };
    union u16ToArr { uint16_t n; uint8_t arr[2]; };
    union u32ToArr { uint32_t n; uint8_t arr[4]; };
    union u64ToArr { uint64_t n; uint8_t arr[8]; };
]]

-- local C = (ffi.os == 'Windows') and ffi.load('msvcrt') or ffi.C
local U = (ffi.os == 'Windows') and ffi.load('ucrtbase') or ffi.C

local conv = {}

do
    local arrToU16, u16ToArr = ffi.typeof 'union arrToU16', ffi.typeof 'union u16ToArr'
    local arrToU32, u32ToArr = ffi.typeof 'union arrToU32', ffi.typeof 'union u32ToArr'
    local arrToU64, u64ToArr = ffi.typeof 'union arrToU64', ffi.typeof 'union u64ToArr'

    if ffi.abi('le') then
        conv.asLE16 = function(arr) return arrToU16(arr).n end
        conv.asLE32 = function(arr) return arrToU32(arr).n end
        conv.asLE64 = function(arr) return arrToU64(arr).n end
        conv.fromLE16 = function(n) return u16ToArr(n).arr end
        conv.fromLE32 = function(n) return u32ToArr(n).arr end
        conv.fromLE64 = function(n) return u64ToArr(n).arr end
        conv.asBE16 = function(arr) return U.bswap16(arrToU16(arr).n) end
        conv.asBE32 = function(arr) return U.bswap32(arrToU32(arr).n) end
        conv.asBE64 = function(arr) return U.bswap64(arrToU64(arr).n) end
        conv.fromBE16 = function(n) return u16ToArr(U.bswap16(n)).arr end
        conv.fromBE32 = function(n) return u32ToArr(U.bswap32(n)).arr end
        conv.fromBE64 = function(n) return u64ToArr(U.bswap64(n)).arr end
    else
        conv.asLE16 = function(arr) return U.bswap16(arrToU16(arr).n) end
        conv.asLE32 = function(arr) return U.bswap32(arrToU32(arr).n) end
        conv.asLE64 = function(arr) return U.bswap64(arrToU64(arr).n) end
        conv.fromLE16 = function(n) return u16ToArr(U.bswap16(n)).arr end
        conv.fromLE32 = function(n) return u32ToArr(U.bswap32(n)).arr end
        conv.fromLE64 = function(n) return u64ToArr(U.bswap64(n)).arr end
        conv.asBE16 = function(arr) return arrToU16(arr).n end
        conv.asBE32 = function(arr) return arrToU32(arr).n end
        conv.asBE64 = function(arr) return arrToU64(arr).n end
        conv.fromBE16 = function(n) return u16ToArr(n).arr end
        conv.fromBE32 = function(n) return u32ToArr(n).arr end
        conv.fromBE64 = function(n) return u64ToArr(n).arr end
    end
end

-- TODO make all cdecls into typeof return calls


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
---@field bufsize number  # fopen buffer size
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

    return conv.asLE16(buf)
end
function BEfn:read_u16()
    local buf = ffi.new("uint8_t[2]")
    local br = U.fread(buf, 1, 2, self.file)
    if br < 2 then
        self:advance(-br)
        error("Reached end of file.")
    end

    return conv.asBE16(buf)
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

    return conv.asLE32(buf)
end
function BEfn:read_u32()
    local buf = ffi.new("uint8_t[4]")
    local br = U.fread(buf, 1, 4, self.file)
    if br < 4 then
        self:advance(-br)
        error("Reached end of file.")
    end

    return conv.asBE32(buf)
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

function LEfn:write_i8(val)
    self:checkWrite()
    assert(U.fputc(val, self.file) ~= -1, "Reached end of file.")

    return self
end
BEfn.write_i8 = LEfn.write_u8

--

function LEfn:write_u16(val)
    self:checkWrite()
    local bw = U.fwrite(conv.fromLE16(val), 1, 2, self.file)
    if bw < 2 then
        self:advance(-bw)
        error("Reached end of file and cannot write further.")
    end

    return self
end
function LEfn:write_i16(val)
    self:checkWrite()
    local bw = U.fwrite(conv.fromLE16(val), 1, 2, self.file)
    if bw < 2 then
        self:advance(-bw)
        error("Reached end of file and cannot write further.")
    end

    return self
end

function BEfn:write_u16(val)
    self:checkWrite()
    local bw = U.fwrite(conv.fromBE16(val), 1, 2, self.file)
    if bw < 2 then
        self:advance(-bw)
        error("Reached end of file and cannot write further.")
    end

    return self
end
BEfn.write_i16 = BEfn.write_u16

--

function LEfn:write_u32(val)
    self:checkWrite()
    local bw = U.fwrite(conv.fromLE32(val), 1, 4, self.file)
    if bw < 4 then
        self:advance(-bw)
        error("Reached end of file and cannot write further.")
    end

    return self
end
function LEfn:write_i32(val)
    self:checkWrite()
    local bw = U.fwrite(conv.fromLE32(val), 1, 4, self.file)
    if bw < 4 then
        self:advance(-bw)
        error("Reached end of file and cannot write further.")
    end

    return self
end

function BEfn:write_u32(val)
    self:checkWrite()
    local bw = U.fwrite(conv.fromBE32(val), 1, 4, self.file)
    if bw < 4 then
        self:advance(-bw)
        error("Reached end of file and cannot write further.")
    end

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