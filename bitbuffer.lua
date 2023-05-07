
local bit = require 'bit'
local ffi = require 'ffi'

local cast, typeof = ffi.cast, ffi.typeof
local band, bor, bxor, rsh, lsh = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

ffi.cdef [[
    void* malloc(size_t size);
    void free(void* mem);
    void* memset(void* ptr, int val, size_t n);
]]

local C = (ffi.os == 'Windows') and ffi.load('msvcrt') or ffi.C

local u8, u16, u32, u64 = typeof 'uint8_t', typeof 'uint16_t', typeof 'uint32_t', typeof 'uint64_t'
local i8, i16, i32, i64 = typeof 'int8_t', typeof 'int16_t', typeof 'int32_t', typeof 'int64_t'



--- Bit buffer
---@class BitBuffer
---@field length integer    # Buffer length in bytes
---@field pos integer       # Byte position to read next
---@field bitpos integer    # Current bit position
---@field ct ffi.cdata*     # Cdata pointer to buffer memory
---@field _ct ffi.cdata* private
local BitBuffer = {}


function BitBuffer__index(self, key)
    if type(key) == 'number' or type(key) == 'cdata' then
        key = tonumber(key)
        assert(key >= 0 and key < self.length, "Index out of bounds")
        return self.ct[key]
    end
    return BitBuffer[key]
end


---@return BitBuffer
function BitBuffer.new(length)
    assert((type(length) == 'number' or type(length) == 'cdata') and length >= 0, "length must be a positive integer.")

    local self = setmetatable({}, {__index = BitBuffer__index})
    self.length = length
    self.pos = 0
    self.bitpos = 0
    self._ct = ffi.gc(C.malloc(self.length), C.free)
    self.ct = cast('uint8_t *', self._ct)

    return self
end

function BitBuffer.from(s)
    assert(type(s) == 'string', "s must be a string source.")
    local self = BitBuffer.new(#s)

    ffi.copy(self.ct, s, self.length)

    return self
end



function BitBuffer:advance(n, bn)
    bn = bn or 0
    n = n + math.floor((self.bitpos + bn) / 8)
    bn = (self.bitpos + bn) % 8
    assert(self.pos + n <= self.length, "Reached end of buffer.")
    local current = self.pos
    local curbit = self.bitpos
    self.pos = current + n
    self.bitpos = bn
    return current, curbit
end

---@param pos integer
---@param bitpos integer?   0 to 7 only
function BitBuffer:seek(pos, bitpos)
    assert(type(pos) == 'number' or type(pos) == 'cdata', "pos must be an integer.")
    if pos < 0 then
        pos = self.length + pos
    end
    self.pos = pos
    self.bitpos = bitpos or self.bitpos
    return self
end



---@return ffi.cdata*
function BitBuffer:read_u8()
    local pos = self:advance(1)
    local x = 0
    if self.bitpos == 0 then
        x = self.ct[pos]
    else
        assert(self.pos+1 < self.length, "Reached end of buffer.")
        x = bor(
            rsh(self.ct[pos], self.bitpos),
            band(
                lsh(self.ct[pos+1], 8-self.bitpos),
                0xff
            )
        )
    end

    return cast(u8, x)
end
function BitBuffer:read_i8() return cast(i8, self:read_u8()) end

---@return fun(self:BitBuffer):ffi.cdata*
local function getReader(nBytes, castType)
    return function(self)
        local x = 0ULL
        for i = 0, nBytes-1 do
            x = bor(x, lsh(self:read_u8(), i*8))
        end
        return cast(castType, x)
    end
end

BitBuffer.read_u16 = getReader(2, u16)
BitBuffer.read_i16 = getReader(2, i16)

BitBuffer.read_u32 = getReader(4, u32)
-- weird things happen with casting directly to an int32_t
function BitBuffer:read_i32() return cast(i32, cast(i64, self:read_u32())) end

BitBuffer.read_u64 = getReader(8, u64)
BitBuffer.read_i64 = getReader(8, i64)



function BitBuffer:read_bit()
    local pos, bitpos = self:advance(0, 1)
    return band(self.ct[pos], lsh(1, bitpos)) > 0 and 1 or 0
end

function BitBuffer:read_bits(nBits)
    assert(nBits >= 0 and nBits <= 64, "nBits out of range")
    local x = 0ULL

    -- read remaining bits of current byte first if incomplete
    local p = (8 - self.bitpos) % 8
    if p > nBits then p = nBits end
    if p > 0 then
        x = bor(x, rsh(self.ct[self.pos], self.bitpos))
        self:advance(0, p)
        nBits = nBits - p
    end

    -- read bytes
    while nBits >= 8 do
        -- x = x | (self.ct[self.pos] << p)
        x = bor(x, lsh(self.ct[self.pos], p))

        self:advance(1)
        p = p + 8
        nBits = nBits - 8
    end

    -- read last bits
    if nBits > 0 then
        -- x = x | ((((self.ct[self.pos] << 8-nBits) & 0xFF) >> 8-nBits) << p)
        x = bor(x, lsh(rsh(band(lsh(self.ct[self.pos], 8-nBits), 0xFF), 8-nBits), p))
        self:advance(0, nBits)
    end

    return x
end



local ffistr = ffi.string
function BitBuffer:read_bytes(len)
    assert((type(len) == 'number' or type(len) == 'cdata') and len >= 0, "len must be a positive integer.")

    local m = cast('uint8_t *', C.malloc(len))
    for i = 0, len-1 do
        m[i] = self:read_u8()
    end

    local str = ffistr(m, len)
    C.free(m)
    return str
end



return BitBuffer

