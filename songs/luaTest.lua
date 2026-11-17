function onCreatePost()
    makeLuaSprite('testSprite', 'lol');
    setProperty('testSprite.scale.x', 2);
    setProperty('testSprite.scale.y', 2);
    screenCenter('testSprite');
    setObjectOrder('testSprite', 5);
    cameraShake('game', 0.5, 0.5);
    addHealth(1);
    addLuaSprite('testSprite',true);
end


function onStepHit() 
    addHealth(1);
end

function onUpdate()
end