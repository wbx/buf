---use-luvit

local bit = require 'bit'
local ffi = require 'ffi'

ffi.cdef [[
    void* malloc(size_t size);
    void free(void* mem);
    void* memset(void* ptr, int val, size_t n);
]]
local C = (ffi.os == 'Windows') and ffi.load('msvcrt') or ffi.C


---@type ByteBuffer
local ByteBuffer = require './bytebuffer'

local function expectError(f, ...)
    assert(pcall(f, ...) == false)
end


---@type ByteBuffer
local bufLE
---@type ByteBuffer
local bufBE
local str = [[abcdefghijklmnopqrstuvwxyz]]
str = str .."\129\131\133\145\167\189\201\202\233\255"
-- 0        .           7           .           15          .           23
-- 61 62 63 64 65 66 67 68 69 6a 6b 6c 6d 6e 6f 70 71 72 73 74 75 76 77 78 79 7a
-- 26 .           31          35
-- 81 83 85 91 a7 bd c9 ca e9 ff


local function init()
    for i = 1, #str do
        io.write(bit.tohex(string.byte(str:sub(i,i)), 2)..' ')
    end
    print()

    bufLE = ByteBuffer.from(str, {rw = true})
    bufBE = ByteBuffer.from(str, {mode = 'be', rw = true})
end


local function test()
    do -- position tests --
        assert(bufLE.pos == 0)
        bufLE:push():seek(4)
        assert(bufLE.pos == 4)
        bufLE:push():seek(10):pop()
        assert(bufLE.pos == 4)
        bufLE:push():seek(20):push():seek(30)
        assert(bufLE.pos == 30)
        bufLE:pop():seek(40):pop()
        assert(bufLE.pos == 4)
        bufLE:seek(-1)
        assert(bufLE.pos == 35)
        bufLE:seek(-2)
        assert(bufLE.pos == 34)
        bufLE:seek(-36)
        assert(bufLE.pos == 0)
        bufLE:seek(-35)
        assert(bufLE.pos == 1)
        bufLE:pop()
        assert(bufLE.pos == 0)
        expectError(function() return bufLE:pop() end)
    end

    do -- positive unsigned tests --
        assert(bufLE:read_u8() == 0x61)
        assert(bufLE:read_u8() == 0x62)
        assert(bufLE:read_u16() == 0x6463)
        assert(bufLE:read_u16() == 0x6665)
        assert(bufLE:read_u32() == 0x6a696867)
        assert(bufLE:read_u32() == 0x6e6d6c6b)
    end

    do -- positive signed tests --
        bufLE:push():seek(0)
        assert(bufLE:read_i8() == 0x61)
        assert(bufLE:read_i8() == 0x62)
        assert(bufLE:read_i16() == 0x6463)
        assert(bufLE:read_i16() == 0x6665)
        assert(bufLE:read_i32() == 0x6a696867)
        assert(bufLE:read_i32() == 0x6e6d6c6b)
    end

    do -- string tests --
        bufLE:pop()
        assert(bufLE:read_bytes(1) == 'o')
        assert(bufLE:read_bytes(2) == 'pq')
        assert(bufLE:read_bytes(4) == 'rstu')
        assert(bufLE:read_bytes(0) == '')
        assert(bufLE:read_bytes(0) == '')
        assert(bufLE:read_bytes(5) == 'vwxyz')
        expectError(function() return bufLE:read_bytes(-1) end)
    end

    do -- index and out-of-bounds tests --
        bufLE:push():seek(0)
        assert(bufLE[0] == bufLE:read_u8())
        assert(bufLE[1] == bufLE:read_u8())
        assert(bufLE[23] == 0x78)
        assert(bufLE[26] == 0x81)
        assert(bufLE[35] == 0xff)
        expectError(function() return bufLE[36] end)
        expectError(function() return bufLE[-1] end)
        bufLE:seek(35)
        assert(bufLE:read_u8() == 0xff)
        expectError(function() return bufLE:read_u8() end)
        bufLE:seek(-2)
        assert(bufLE:read_u8() == 0xe9)
        expectError(function() return bufLE:read_u32() end)
        expectError(function() return bufLE:read_i32() end)
        expectError(function() return bufLE:read_u16() end)
        expectError(function() return bufLE:read_i16() end)
        assert(bufLE:read_u8() == 0xff)
        expectError(function() return bufLE:read_i8() end)
        bufLE:seek(-1)
        assert(bufLE:read_bytes(1) == '\255')
        expectError(function() return bufLE:read_bytes(1) end)
    end

    do -- negative unsigned tests --
        bufLE:pop():push()
        assert(bufLE:read_u8() == 0x81)
        assert(bufLE:read_u8() == 0x83)
        assert(bufLE:read_u16() == 0x9185)
        assert(bufLE:read_u16() == 0xbda7)
        assert(bufLE:read_u32() == 0xffe9cac9)
    end

    do -- negative signed tests --
        bufLE:pop()
        assert(bufLE:read_i8() == 0x81 - 0x100)
        assert(bufLE:read_i8() == 0x83 - 0x100)
        assert(bufLE:read_i16() == 0x9185 - 0x10000)
        assert(bufLE:read_i16() == 0xbda7 - 0x10000)
        assert(bufLE:read_i32() == 0xffe9cac9 - 0xffffffff - 0x1)
    end

    do -- mixed signed test --
        bufLE:seek(24)
        assert(bufLE:read_i32() == 0x83817a79 - 0xffffffff - 0x1)
    end

    do -- write-read tests --
        bufLE:push():write_u8(0xa2):pop()
        assert(bufLE:read_u8() == 0xa2)
        bufLE:push():write_u16(0xb3c4):pop()
        assert(bufLE:read_u16() == 0xb3c4)
        bufLE:push():write_u32(0xb3c4d5e6):pop()
        assert(bufLE:read_u32() == 0xb3c4d5e6)
        bufLE:seek(0)
        bufLE:push():write_bytes('qwertyuiopqwertyuiopqwertyuiop'):pop()
        assert(bufLE:read_bytes(30) == 'qwertyuiopqwertyuiopqwertyuiop')
    end


    --- Big-endian tests ---

    do -- positive unsigned tests --
        bufBE:seek(0)
        assert(bufBE:read_u8() == 0x61)
        assert(bufBE:read_u8() == 0x62)
        assert(bufBE:read_u16() == 0x6364)
        assert(bufBE:read_u16() == 0x6566)
        assert(bufBE:read_u32() == 0x6768696a)
        assert(bufBE:read_u32() == 0x6b6c6d6e)
    end

    do -- positive signed tests --
        bufBE:seek(0)
        assert(bufBE:read_i8() == 0x61)
        assert(bufBE:read_i8() == 0x62)
        assert(bufBE:read_i16() == 0x6364)
        assert(bufBE:read_i16() == 0x6566)
        assert(bufBE:read_i32() == 0x6768696a)
        assert(bufBE:read_i32() == 0x6b6c6d6e)
    end

    do -- negative unsigned tests --
        bufBE:seek(26):push()
        assert(bufBE:read_u8() == 0x81)
        assert(bufBE:read_u8() == 0x83)
        assert(bufBE:read_u16() == 0x8591)
        assert(bufBE:read_u16() == 0xa7bd)
        assert(bufBE:read_u32() == 0xc9cae9ff)
    end

    do -- negative signed tests --
        bufBE:pop()
        assert(bufBE:read_i8() == 0x81 - 0x100)
        assert(bufBE:read_i8() == 0x83 - 0x100)
        assert(bufBE:read_i16() == 0x8591 - 0x10000)
        assert(bufBE:read_i16() == 0xa7bd - 0x10000)
        assert(bufBE:read_i32() == 0xc9cae9ff - 0xffffffff - 0x1)
    end

    do -- mixed signed test --
        bufBE:seek(24)
        assert(bufBE:read_i32() == 0x797a8183)
    end

    do -- write-read tests --
        bufBE:push():write_u8(0xa2):pop()
        assert(bufBE:read_u8() == 0xa2)
        bufBE:push():write_u16(0xb3c4):pop()
        assert(bufBE:read_u16() == 0xb3c4)
        bufBE:push():write_u32(0xb3c4d5e6):pop()
        assert(bufBE:read_u32() == 0xb3c4d5e6)
        bufBE:seek(0)
        bufBE:push():write_bytes('qwertyuiopqwertyuiopqwertyuiop'):pop()
        assert(bufBE:read_bytes(30) == 'qwertyuiopqwertyuiopqwertyuiop')
    end

    do -- GC test --
        do
            bufLE:seek(0):write_bytes("abcdefghijklmnopqrstuvwxyz\129\131\133\145\167\189\201\202\233\255")
        end
        str = nil
        bufBE = nil
        collectgarbage()
        collectgarbage()
        collectgarbage()

        print()
        for i = 0, 65535 do
            local cd = ffi.new('uint8_t[1024]',("qwertyuiopqwertyuiopqwertyuiop"):rep(32))
            local ma = ffi.gc(C.malloc(1024), C.free)
            local mp = ffi.cast('uint8_t*', ma)
            ffi.copy(mp, ("qwertyuiopqwertyuiopqwertyuiop"):upper():rep(32))
            io.write(('\r%05d %s'):format(
                i,
                bit.tohex(cd[math.random(0,1023)], 2),
                bit.tohex(mp[math.random(0,1023)], 2)
            ))
        end
        print()

        collectgarbage()
        collectgarbage()
        collectgarbage()

        local cmp = "abcdefghijklmnopqrstuvwxyz\129\131\133\145\167\189\201\202\233\255"

        bufLE:seek(0)
        assert(bufLE:read_bytes(#cmp) == cmp)
    end
end



init()

test()

print('pass')

