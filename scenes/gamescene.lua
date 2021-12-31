GameScene = Object:extend()
local size
local threadpool = {}
-- load up some threads so that chunk meshing won't block the main thread
for i=1, 8 do
    threadpool[i] = love.thread.newThread "lib/chunkremesh.lua"
end
local threadchannels = {}
local texturepack = lg.newImage "assets/texturepack.png"
local wasLeftDown, wasRightDown, rightDown, leftDown

local renderDistance = 5

-- create the mesh for the block cursor
local blockCursor, blockCursorVisible
do
    local a = -0.005
    local b = 1.005
    blockCursor = g3d.newModel{
        {a,a,a}, {b,a,a}, {b,a,a},
        {a,a,a}, {a,a,b}, {a,a,b},
        {b,a,b}, {a,a,b}, {a,a,b},
        {b,a,b}, {b,a,a}, {b,a,a},

        {a,b,a}, {b,b,a}, {b,b,a},
        {a,b,a}, {a,b,b}, {a,b,b},
        {b,b,b}, {a,b,b}, {a,b,b},
        {b,b,b}, {b,b,a}, {b,b,a},

        {a,a,a}, {a,b,a}, {a,b,a},
        {b,a,a}, {b,b,a}, {b,b,a},
        {a,a,b}, {a,b,b}, {a,b,b},
        {b,a,b}, {b,b,b}, {b,b,b},
    }
end

function GameScene:init()
    size = Chunk.size
    self.thingList = {}
    self.chunkMap = {}
    self.remeshQueue = {}
    self.chunkCreationsThisFrame = 0
    self.updatedThisFrame = false
end

function GameScene:addThing(thing)
    if not thing then return end
    table.insert(self.thingList, thing)
    return thing
end

function GameScene:removeThing(index)
    if not index then return end
    local thing = self.thingList[index]
    table.remove(self.thingList, index)
    return thing
end

local function updateChunk(self, x, y, z)
    x = x + math.floor(g3d.camera.position[1]/size)
    y = y + math.floor(g3d.camera.position[2]/size)
    z = z + math.floor(g3d.camera.position[3]/size)
    local hash = ("%d/%d/%d"):format(x, y, z)
    if self.chunkMap[hash] then
        self.chunkMap[hash].frames = 0
    else
        local chunk = Chunk(x, y, z)
        self.chunkMap[hash] = chunk
        self.chunkCreationsThisFrame = self.chunkCreationsThisFrame + 1

        -- this chunk was just created, so update all the chunks around it
        self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x+1,y,z)])
        self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x-1,y,z)])
        self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y+1,z)])
        self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y-1,z)])
        self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y,z+1)])
        self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y,z-1)])
    end
end

function GameScene:update(dt)
    -- update all the things in the scene
    -- remove the dead things
    local i = 1
    while i <= #self.thingList do
        local thing = self.thingList[i]
        if not thing.dead then
            thing:update()
            i = i + 1
        else
            self:removeThing(i)
        end
    end

    -- collect mouse inputs
    wasLeftDown, wasRightDown = leftDown, rightDown
    leftDown, rightDown = love.mouse.isDown(1), love.mouse.isDown(2)
    leftClick, rightClick = leftDown and not wasLeftDown, rightDown and not wasRightDown

    self.updatedThisFrame = true
    g3d.camera.firstPersonMovement(dt)

    -- generate a "bubble" of loaded chunks around the camera
    local bubbleWidth = renderDistance
    local bubbleHeight = math.floor(renderDistance * 0.75)
    local creationLimit = 1
    self.chunkCreationsThisFrame = 0
    for r=0, bubbleWidth do
        for a=0, math.pi*2, math.pi*2/(8*r) do
            local h = math.floor(math.cos(r*(math.pi/2)/bubbleWidth)*bubbleHeight + 0.5)
            for y=0, h do
                local x, z = math.floor(math.cos(a)*r + 0.5), math.floor(math.sin(a)*r + 0.5)
                if y ~= 0 then
                    updateChunk(self, x, -y, z)
                end
                updateChunk(self, x, y, z)
                if self.chunkCreationsThisFrame >= creationLimit then break end
            end
        end
    end

    -- count how many threads are being used right now
    local threadusage = 0
    for _, thread in ipairs(threadpool) do
        if thread:isRunning() then
            threadusage = threadusage + 1
        end

        local err = thread:getError()
        assert(not err, err)
    end

    -- listen for finished meshes on the thread channels
    for channel, chunk in pairs(threadchannels) do
        local data = love.thread.getChannel(channel):pop()
        if data then
            threadchannels[channel] = nil
            if chunk.model then chunk.model.mesh:release() end
            chunk.model = nil
            if data.count > 0 then
                chunk.model = g3d.newModel(data.count, texturepack)
                chunk.model.mesh:setVertices(data.data)
                chunk.model:setTranslation(chunk.x, chunk.y, chunk.z)
                chunk.inRemeshQueue = false
                break
            end
        end
    end

    -- remesh the chunks in the queue
    -- NOTE: if this happens multiple times in a frame, weird things can happen? idk why
    if threadusage < #threadpool and #self.remeshQueue > 0 then
        local chunk
        local ok = false
        repeat
            chunk = table.remove(self.remeshQueue, 1)
        until not chunk or self.chunkMap[chunk.hash]

        if chunk and not chunk.dead then
            for _, thread in ipairs(threadpool) do
                if not thread:isRunning() then
                    -- send over the neighboring chunks to the thread
                    -- so that voxels on the edges can face themselves properly
                    local x, y, z = chunk.cx, chunk.cy, chunk.cz
                    local neighbor, n1, n2, n3, n4, n5, n6
                    neighbor = self.chunkMap[("%d/%d/%d"):format(x+1,y,z)]
                    if neighbor and not neighbor.dead then n1 = neighbor.data end
                    neighbor = self.chunkMap[("%d/%d/%d"):format(x-1,y,z)]
                    if neighbor and not neighbor.dead then n2 = neighbor.data end
                    neighbor = self.chunkMap[("%d/%d/%d"):format(x,y+1,z)]
                    if neighbor and not neighbor.dead then n3 = neighbor.data end
                    neighbor = self.chunkMap[("%d/%d/%d"):format(x,y-1,z)]
                    if neighbor and not neighbor.dead then n4 = neighbor.data end
                    neighbor = self.chunkMap[("%d/%d/%d"):format(x,y,z+1)]
                    if neighbor and not neighbor.dead then n5 = neighbor.data end
                    neighbor = self.chunkMap[("%d/%d/%d"):format(x,y,z-1)]
                    if neighbor and not neighbor.dead then n6 = neighbor.data end

                    thread:start(chunk.hash, chunk.data, n1, n2, n3, n4, n5, n6)
                    threadchannels[chunk.hash] = chunk
                    break
                end
            end
        end
    end

    -- left click to destroy blocks
    -- casts a ray from the camera five blocks in the look vector
    -- finds the first intersecting block
    local vx, vy, vz = g3d.camera.getLookVector()
    local x, y, z = g3d.camera.position[1], g3d.camera.position[2], g3d.camera.position[3]
    local step = 0.1
    local floor = math.floor
    local buildx, buildy, buildz
    blockCursorVisible = false
    for i=step, 5, step do
        local bx, by, bz = floor(x + vx*i), floor(y + vy*i), floor(z + vz*i)
        local chunk = self:getChunkFromWorld(bx, by, bz)
        if chunk then
            local lx, ly, lz = bx%size, by%size, bz%size
            if chunk:getBlock(lx,ly,lz) ~= 0 then
                blockCursor:setTranslation(bx, by, bz)
                blockCursorVisible = true

                -- store the last position the ray was at
                -- as the position for building a block
                local li = i - step
                buildx, buildy, buildz = floor(x + vx*li), floor(y + vy*li), floor(z + vz*li)

                if leftClick then
                    local x, y, z = chunk.cx, chunk.cy, chunk.cz
                    chunk:setBlock(lx,ly,lz, 0)
                    self:requestRemesh(chunk, true)
                    if lx >= size-1 then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x+1,y,z)], true) end
                    if lx <= 0      then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x-1,y,z)], true) end
                    if ly >= size-1 then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y+1,z)], true) end
                    if ly <= 0      then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y-1,z)], true) end
                    if lz >= size-1 then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y,z+1)], true) end
                    if lz <= 0      then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y,z-1)], true) end
                end

                break
            end
        end
    end

    -- right click to place blocks
    if rightClick and buildx then
        local chunk = self:getChunkFromWorld(buildx, buildy, buildz)
        local lx, ly, lz = buildx%size, buildy%size, buildz%size
        if chunk then
            local x, y, z = chunk.cx, chunk.cy, chunk.cz
            chunk:setBlock(lx, ly, lz, 1)
            self:requestRemesh(chunk, true)
            if lx >= size-1 then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x+1,y,z)], true) end
            if lx <= 0      then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x-1,y,z)], true) end
            if ly >= size-1 then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y+1,z)], true) end
            if ly <= 0      then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y-1,z)], true) end
            if lz >= size-1 then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y,z+1)], true) end
            if lz <= 0      then self:requestRemesh(self.chunkMap[("%d/%d/%d"):format(x,y,z-1)], true) end
        end
    end
end

function GameScene:mousemoved(x, y, dx, dy)
    g3d.camera.firstPersonLook(dx, dy)
end

function GameScene:draw()
    lg.clear(lume.color "#4488ff")

    -- draw all the things in the scene
    for _, thing in ipairs(self.thingList) do
        thing:draw()
    end

    lg.setColor(1,1,1)
    for hash, chunk in pairs(self.chunkMap) do
        chunk:draw()

        if self.updatedThisFrame then
            chunk.frames = chunk.frames + 1
            if chunk.frames > 100 then chunk:destroy() end
        end
    end

    self.updatedThisFrame = false

    if blockCursorVisible then
        lg.setColor(0,0,0)
        lg.setWireframe(true)
        blockCursor:draw()
        lg.setWireframe(false)
    end
end

function GameScene:getChunkFromWorld(x,y,z)
    local floor = math.floor
    return self.chunkMap[("%d/%d/%d"):format(floor(x/size),floor(y/size),floor(z/size))]
end

function GameScene:getBlockFromWorld(x,y,z)
    local floor = math.floor
    local chunk = self.chunkMap[("%d/%d/%d"):format(floor(x/size),floor(y/size),floor(z/size))]
    if chunk then return chunk:getBlock(x%size, y%size, z%size) end
    return -1
end

function GameScene:setBlockFromWorld(x,y,z, value)
    local floor = math.floor
    local chunk = self.chunkMap[("%d/%d/%d"):format(floor(x/size),floor(y/size),floor(z/size))]
    if chunk then chunk:setBlock(x%size, y%size, z%size, value) end
end

function GameScene:requestRemesh(chunk, first)
    -- don't add a nil chunk or a chunk that's already in the queue
    if not chunk then return end
    local x, y, z = chunk.cx, chunk.cy, chunk.cz
    if not self.chunkMap[("%d/%d/%d"):format(x+1,y,z)] then return end
    if not self.chunkMap[("%d/%d/%d"):format(x-1,y,z)] then return end
    if not self.chunkMap[("%d/%d/%d"):format(x,y+1,z)] then return end
    if not self.chunkMap[("%d/%d/%d"):format(x,y-1,z)] then return end
    if not self.chunkMap[("%d/%d/%d"):format(x,y,z+1)] then return end
    if not self.chunkMap[("%d/%d/%d"):format(x,y,z-1)] then return end
    chunk.inRemeshQueue = true
    if first then
        table.insert(self.remeshQueue, 1, chunk)
    else
        table.insert(self.remeshQueue, chunk)
    end
end
