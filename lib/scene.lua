local scene

return function (newscene)
    if newscene then
        scene = newscene
        love.audio.stop()
        if scene.init then scene:init() end
        love.timer.step()
    end

    return scene
end
