--->use-luvit<---

local fs = require 'fs'
local bit = require 'bit'


---@type FileBuffer
local FileBuffer = require './filebuffer'

local function expectError(f, ...)
    assert(pcall(f, ...) == false)
end


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
end


local function test()
    fs.writeFileSync("filebuftest.bin", str)
    local bufLE = assert(FileBuffer.from("filebuftest.bin", {rw = true}))

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
        bufLE:push():seek(10)
        assert(bufLE:read_u64() == 0x7271706f6e6d6c6bULL)
        assert(bufLE:read_u64() == 0x7a79787776757473ULL)
    end

    do -- positive signed tests --
        bufLE:seek(0)
        assert(bufLE:read_i8() == 0x61)
        assert(bufLE:read_i8() == 0x62)
        assert(bufLE:read_i16() == 0x6463)
        assert(bufLE:read_i16() == 0x6665)
        assert(bufLE:read_i32() == 0x6a696867)
        assert(bufLE:read_i32() == 0x6e6d6c6b)
        bufLE:seek(10)
        assert(bufLE:read_i64() == 0x7271706f6e6d6c6bLL)
        assert(bufLE:read_i64() == 0x7a79787776757473LL)
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
        expectError(function() return bufLE:read_u64() end)
        expectError(function() return bufLE:read_i64() end)
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
        bufLE:seek(28)
        assert(bufLE:read_u64() == 0xffe9cac9bda79185ULL)
    end

    do -- negative signed tests --
        bufLE:pop()
        assert(bufLE:read_i8() == 0x81 - 0x100)
        assert(bufLE:read_i8() == 0x83 - 0x100)
        assert(bufLE:read_i16() == 0x9185 - 0x10000)
        assert(bufLE:read_i16() == 0xbda7 - 0x10000)
        assert(bufLE:read_i32() == 0xffe9cac9 - 0xffffffff - 0x1)
        bufLE:seek(28)
        assert(bufLE:read_i64() == 0xffe9cac9bda79185LL)
    end

    do -- mixed signed test --
        bufLE:seek(24)
        assert(bufLE:read_i32() == 0x83817a79 - 0xffffffff - 0x1)
        bufLE:seek(22)
        assert(bufLE:read_i64() == 0x918583817a797877LL)
    end

    do -- write-read tests --
        -- unsigned
        bufLE:seek(8)
        bufLE:push():write_u8(0xa2):pop()
        assert(bufLE:read_u8() == 0xa2)
        bufLE:push():write_u16(0xb3c4):pop()
        assert(bufLE:read_u16() == 0xb3c4)
        bufLE:push():write_u32(0xb3c4d5e6):pop()
        assert(bufLE:read_u32() == 0xb3c4d5e6)
        bufLE:push():write_u64(0xf0e1d2c3b4a59687ULL):pop()
        assert(bufLE:read_u64() == 0xf0e1d2c3b4a59687ULL)
        -- signed
        bufLE:seek(8)
        bufLE:push():write_i8(0xa2):pop()
        assert(bufLE:read_i8() == 0xa2 - 0x100)
        bufLE:push():write_i16(0xb3c4):pop()
        assert(bufLE:read_i16() == 0xb3c4 - 0x10000)
        bufLE:push():write_i32(0xb3c4d5e6):pop()
        assert(bufLE:read_i32() == 0xb3c4d5e6 - 0xffffffff - 0x1)
        bufLE:push():write_i64(0xf0e1d2c3b4a59687LL):pop()
        assert(bufLE:read_i64() == 0xf0e1d2c3b4a59687LL)
        -- string
        bufLE:seek(0)
        bufLE:push():write_bytes('qwertyuiopqwertyuiopqwertyuiop'):pop()
        assert(bufLE:read_bytes(30) == 'qwertyuiopqwertyuiopqwertyuiop')
    end

    bufLE:close()


    --- Big-endian tests ---
    fs.writeFileSync("filebuftest.bin", str)
    local bufBE = assert(FileBuffer.from("filebuftest.bin", {mode = 'be', rw = true}))

    do -- positive unsigned tests --
        bufBE:seek(0)
        assert(bufBE:read_u8() == 0x61)
        assert(bufBE:read_u8() == 0x62)
        assert(bufBE:read_u16() == 0x6364)
        assert(bufBE:read_u16() == 0x6566)
        assert(bufBE:read_u32() == 0x6768696a)
        bufBE:push()
        assert(bufBE:read_u32() == 0x6b6c6d6e)
        bufBE:pop()
        assert(bufBE:read_u64() == 0x6b6c6d6e6f707172ULL)
        assert(bufBE:read_u64() == 0x737475767778797aULL)
    end

    do -- positive signed tests --
        bufBE:seek(0)
        assert(bufBE:read_i8() == 0x61)
        assert(bufBE:read_i8() == 0x62)
        assert(bufBE:read_i16() == 0x6364)
        assert(bufBE:read_i16() == 0x6566)
        assert(bufBE:read_i32() == 0x6768696a)
        bufBE:push()
        assert(bufBE:read_i32() == 0x6b6c6d6e)
        bufBE:pop()
        assert(bufBE:read_u64() == 0x6b6c6d6e6f707172LL)
        assert(bufBE:read_u64() == 0x737475767778797aLL)
    end

    do -- negative unsigned tests --
        bufBE:seek(26):push()
        assert(bufBE:read_u8() == 0x81)
        assert(bufBE:read_u8() == 0x83)
        assert(bufBE:read_u16() == 0x8591)
        assert(bufBE:read_u16() == 0xa7bd)
        assert(bufBE:read_u32() == 0xc9cae9ff)
        bufBE:seek(28)
        assert(bufBE:read_u64() == 0x8591a7bdc9cae9ffULL)
    end

    do -- negative signed tests --
        bufBE:pop()
        assert(bufBE:read_i8() == 0x81 - 0x100)
        assert(bufBE:read_i8() == 0x83 - 0x100)
        assert(bufBE:read_i16() == 0x8591 - 0x10000)
        assert(bufBE:read_i16() == 0xa7bd - 0x10000)
        assert(bufBE:read_i32() == 0xc9cae9ff - 0xffffffff - 0x1)
        bufBE:seek(28)
        assert(bufBE:read_u64() == 0x8591a7bdc9cae9ffLL)
    end

    do -- mixed signed test --
        bufBE:seek(24)
        assert(bufBE:read_i32() == 0x797a8183)
        bufBE:seek(22)
        assert(bufBE:read_i64() == 0x7778797a81838591LL)
    end

    do -- write-read tests --
        -- unsigned
        bufBE:seek(8)
        bufBE:push():write_u8(0xa2):pop()
        assert(bufBE:read_u8() == 0xa2)
        bufBE:push():write_u16(0xb3c4):pop()
        assert(bufBE:read_u16() == 0xb3c4)
        bufBE:push():write_u32(0xb3c4d5e6):pop()
        assert(bufBE:read_u32() == 0xb3c4d5e6)
        bufBE:push():write_u64(0xf0e1d2c3b4a59687ULL):pop()
        assert(bufBE:read_u64() == 0xf0e1d2c3b4a59687ULL)
        -- signed
        bufBE:seek(8)
        bufBE:push():write_i8(0xa2):pop()
        assert(bufBE:read_i8() == 0xa2 - 0x100)
        bufBE:push():write_i16(0xb3c4):pop()
        assert(bufBE:read_i16() == 0xb3c4 - 0x10000)
        bufBE:push():write_i32(0xb3c4d5e6):pop()
        assert(bufBE:read_i32() == 0xb3c4d5e6 - 0xffffffff - 0x1)
        bufBE:push():write_i64(0xf0e1d2c3b4a59687LL):pop()
        assert(bufBE:read_i64() == 0xf0e1d2c3b4a59687LL)
        -- string
        bufBE:seek(0)
        bufBE:push():write_bytes('qwertyuiopqwertyuiopqwertyuiop'):pop()
        assert(bufBE:read_bytes(30) == 'qwertyuiopqwertyuiopqwertyuiop')
    end

    bufBE:close()
end



init()

test()

fs.unlinkSync("filebuftest.bin")
print('pass')
