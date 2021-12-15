-- object oriented programming system (oops)
-- by groverburger, february 2021
-- MIT License

return function(parent)
    local class = {super = parent}
    local classMetatable = {__index = parent}
    local instanceMetatable = {__index = class}

    -- instantiate a class by calling it like a function
    function classMetatable:__call(...)
        local instance = setmetatable({}, instanceMetatable)
        if class.new then
            instance:new(...)
        end
        return instance
    end

    -- a class's metatable contains __call to instantiate it
    -- as well as a __index pointing to its parent class if it has one
    setmetatable(class, classMetatable)

    -- get the class that this instance is derived from
    function class:getClass()
        return class
    end

    -- check if this instance is a derived from this class - this checks the parent classes as well
    function class:instanceOf(someClass)
        return class == someClass or (parent and parent:instanceOf(someClass))
    end

    function class:implement(otherClass)
        for i, v in pairs(otherClass) do
            if not self[i] and type(v) == "function" then
                self[i] = v
            end
        end
    end

    return class
end
