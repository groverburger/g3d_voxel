lg = love.graphics
lg.setDefaultFilter "nearest"
io.stdout:setvbuf "no"

g3d = require "lib/g3d"
lume = require "lib/lume"
class = require "lib/oops"
scene = require "lib/scene"

require "things/chunk"
require "scenes/gamescene"

function love.load(args)
    scene(GameScene())
end

function love.update(dt)
    local scene = scene()
    if scene.update then
        scene:update(dt)
    end
end

function love.draw()
    local scene = scene()
    if scene.draw then
        scene:draw()
    end
end

function love.mousemoved(x, y, dx, dy)
    local scene = scene()
    if scene.mousemoved then
        scene:mousemoved(x, y, dx, dy)
    end
end

function love.keypressed(k)
    if k == "escape" then
        love.event.push "quit"
    end
end

function love.resize(w, h)
    g3d.camera.aspectRatio = w / h
    g3d.camera.updateProjectionMatrix()
end
