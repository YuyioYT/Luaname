
function postCreate() {
    makeLuaSprite('testSprite', 'lol');
    scaleObject('testSprite', 1, 1);
    screenCenter('testSprite');
    setObjectOrder('testSprite', 5);
    cameraShake('game', 0.5, 0.5);
    addHealth(1);
       addLuaSprite('testSprite',true);
}


function stepHit(curStep:Int) {
    addHealth(1);
    switch(curStep) {
        case 15:
            doTweenColor('testSprite', "testSprite", "FF2A00", 1, 'linear');
    }
}

function update(elapsed:Float) {
    if (mouseReleased())
        trace('mouseClicked');
}