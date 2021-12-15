require "love.math"
require "love.data"
ffi = require "ffi"

channel, blockdata, n1, n2, n3, n4, n5, n6 = ...
local blockdatapointer = ffi.cast("uint8_t *", blockdata:getFFIPointer())
local n1p = n1 and ffi.cast("uint8_t *", n1:getFFIPointer())
local n2p = n2 and ffi.cast("uint8_t *", n2:getFFIPointer())
local n3p = n3 and ffi.cast("uint8_t *", n3:getFFIPointer())
local n4p = n4 and ffi.cast("uint8_t *", n4:getFFIPointer())
local n5p = n5 and ffi.cast("uint8_t *", n5:getFFIPointer())
local n6p = n6 and ffi.cast("uint8_t *", n6:getFFIPointer())

u1, v1 = 3/8, 1/8
u2, v2 = 0, 0
c1 = 1
c2 = 0.75
c3 = 0.5

function clamp(n, min, max)
    if min < max then
        return math.min(math.max(n, min), max)
    end

    return math.min(math.max(n, max), min)
end

function map(n, start1, stop1, start2, stop2, withinBounds)
    local newval = (n - start1) / (stop1 - start1) * (stop2 - start2) + start2

    if not withinBounds then
        return newval
    end

    return clamp(newval, start2, stop2)
end

function getBlock(pointer, x,y,z)
    local i = x + size*y + size*size*z

    -- if this block is outside of the chunk, check the neighboring chunks if they exist
    if x >= size then return n1p and getBlock(n1p, x%size,y%size,z%size) or -1 end
    if x <  0    then return n2p and getBlock(n2p, x%size,y%size,z%size) or -1 end
    if y >= size then return n3p and getBlock(n3p, x%size,y%size,z%size) or -1 end
    if y <  0    then return n4p and getBlock(n4p, x%size,y%size,z%size) or -1 end
    if z >= size then return n5p and getBlock(n5p, x%size,y%size,z%size) or -1 end
    if z <  0    then return n6p and getBlock(n6p, x%size,y%size,z%size) or -1 end

    return pointer[i]
end

facecount = 0
size = 16
for x=0, size-1 do
    for y=0, size-1 do
        for z=0, size-1 do
            if getBlock(blockdatapointer, x,y,z) ~= 0 then
                if getBlock(blockdatapointer, x+1,y,z) == 0 then facecount = facecount + 1 end
                if getBlock(blockdatapointer, x-1,y,z) == 0 then facecount = facecount + 1 end
                if getBlock(blockdatapointer, x,y+1,z) == 0 then facecount = facecount + 1 end
                if getBlock(blockdatapointer, x,y-1,z) == 0 then facecount = facecount + 1 end
                if getBlock(blockdatapointer, x,y,z+1) == 0 then facecount = facecount + 1 end
                if getBlock(blockdatapointer, x,y,z-1) == 0 then facecount = facecount + 1 end
            end
        end
    end
end

ffi.cdef([[
    struct vertex {
        float x, y, z;
        float u, v;
        float nx, ny, nz;
        uint8_t r, g, b, a;
    }
]])

count = facecount*6
if count > 0 then
    data = love.data.newByteData(count*ffi.sizeof("struct vertex"))
    datapointer = ffi.cast("struct vertex *", data:getFFIPointer())
    dataindex = 0

    function addFace(x,y,z, mx,my,mz, u,v, c)
        for i=1, 6 do
            local primary = i%2 == 1
            local secondary = i > 2 and i < 6
            datapointer[dataindex].x  = x + (mx == 1 and primary and 1 or 0) + (mx == 2 and secondary and 1 or 0)
            datapointer[dataindex].y  = y + (my == 1 and primary and 1 or 0) + (my == 2 and secondary and 1 or 0)
            datapointer[dataindex].z  = z + (mz == 1 and primary and 1 or 0) + (mz == 2 and secondary and 1 or 0)
            datapointer[dataindex].u  = u + (primary   and 1/8 or 0)
            datapointer[dataindex].v  = v + (secondary and 1/8 or 0)
            datapointer[dataindex].nx = 0
            datapointer[dataindex].ny = 1
            datapointer[dataindex].nz = 0
            datapointer[dataindex].r  = c*255
            datapointer[dataindex].g  = c*255
            datapointer[dataindex].b  = c*255
            datapointer[dataindex].a  = 255
            dataindex = dataindex + 1
        end
    end

    for x=0, size-1 do
        for y=0, size-1 do
            for z=0, size-1 do
                if getBlock(blockdatapointer, x,y,z) ~= 0 then
                    if getBlock(blockdatapointer, x-1,y,z) == 0 then addFace(x,y,z,   0,1,2, u1,v1,c2) end
                    if getBlock(blockdatapointer, x+1,y,z) == 0 then addFace(x+1,y,z, 0,1,2, u1,v1,c2) end
                    if getBlock(blockdatapointer, x,y-1,z) == 0 then addFace(x,y,z,   1,0,2, u1,v1,c1) end
                    if getBlock(blockdatapointer, x,y+1,z) == 0 then addFace(x,y+1,z, 1,0,2, u1,v1,c1) end
                    if getBlock(blockdatapointer, x,y,z-1) == 0 then addFace(x,y,z,   1,2,0, u1,v1,c3) end
                    if getBlock(blockdatapointer, x,y,z+1) == 0 then addFace(x,y,z+1, 1,2,0, u2,v2,c1) end
                end
            end
        end
    end

    love.thread.getChannel(channel):push{data = data, count = count}
else
    love.thread.getChannel(channel):push{data = nil, count = count}
end
