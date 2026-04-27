local tween = {}
function tween.linear(a, b, dt)
    local step = 100 * dt
    if math.abs(a - b) <= step then return b end
    return a + (a < b and step or -step)
end
function tween.expo(a, b, dt)
    return a + (b - a) * (1 - math.exp(-15 * dt))
end
return tween