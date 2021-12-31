local size = 16
local ffi = require "ffi"

Chunk = Object:extend()
Chunk.size = size

function Chunk:new(x,y,z)
    self.data = {}
    self.cx = x
    self.cy = y
    self.cz = z
    self.x = x*size
    self.y = y*size
    self.z = z*size
    self.hash = ("%d/%d/%d"):format(x,y,z)
    self.frames = 0
    self.inRemeshQueue = false

    local data = love.data.newByteData(size*size*size*ffi.sizeof("uint8_t"))
    local datapointer = ffi.cast("uint8_t *", data:getFFIPointer())
    local f = 0.125
    for i=0, size*size*size - 1 do
        local x, y, z = i%size + self.x, math.floor(i/size)%size + self.y, math.floor(i/(size*size)) + self.z
        datapointer[i] = love.math.noise(x*f,y*f,z*f) > (z+32)/64 and 1 or 0
    end
    self.data = data
    self.datapointer = datapointer
end

function Chunk:getBlock(x,y,z)
    if self.dead then return -1 end

    if x >= 0 and y >= 0 and z >= 0 and x < size and y < size and z < size then
        local i = x + size*y + size*size*z
        return self.datapointer[i]
    end

    local chunk = scene():getChunkFromWorld(self.x+x,self.y+y,self.z+z)
    if chunk then return chunk:getBlock(x%size,y%size,z%size) end
    return -1
end

function Chunk:setBlock(x,y,z, value)
    if self.dead then return -1 end

    if x >= 0 and y >= 0 and z >= 0 and x < size and y < size and z < size then
        local i = x + size*y + size*size*z
        self.datapointer[i] = value
        return
    end

    local chunk = scene():getChunkFromWorld(self.x+x,self.y+y,self.z+z)
    if chunk then return chunk:setBlock(x%size,y%size,z%size, value) end
end

function Chunk:draw()
    if self.model and not self.dead then
        self.model:draw()
    end
end

function Chunk:destroy()
    if self.model then self.model.mesh:release() end
    self.dead = true
    self.data:release()
    scene().chunkMap[self.hash] = nil
end
