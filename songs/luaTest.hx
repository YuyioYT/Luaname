
nightColor = '0xFF878787';
function create(){

makeLuaSprite('sky', 'farmnight/rb/bg', -1500, -1200);
setScrollFactor('sky', 0, 0);
addLuaSprite('sky', false);

makeLuaSprite('nubes', 'farmnight/rb/nubes2', -1500, -1200);
setScrollFactor('nubes', 0, 0);
addLuaSprite('nubes', false);

makeLuaSprite('hills', 'farmnight/rb/hills', -1500, -1500);
setScrollFactor('hills', 0.1, 0.1);
addLuaSprite('hills', false);

makeLuaSprite('nubes1', 'farmnight/rb/nubes', -1500, -1200);
setScrollFactor('nubes1', 0, 0);
scaleObject('nubes1', 0.7, 0.7);
addLuaSprite('nubes1', false);

makeLuaSprite('rockswithfarm', 'farmnight/rb/rockswithfarm', -1500, -2000);
setScrollFactor('rockswithfarm', 0, 0);
addLuaSprite('rockswithfarm', false);   

makeLuaSprite('rocks', 'farmnight/rb/rock', -1500, -2000);
setScrollFactor('rocks', 0.3, 0.3);
addLuaSprite('rocks', false);

makeLuaSprite('rocks2', 'farmnight/rb/rock2', -1500, -2000);
setScrollFactor('rocks2', 0.3, 0.3);
addLuaSprite('rocks2', false);

makeLuaSprite('ground', 'farmnight/rb/ground', -1500, -1200);
setScrollFactor('ground', 1, 1);
addLuaSprite('ground', false);

doTweenColor('obj1ColorTween', 'obj1', nightColor, 0.0001);
	doTweenColor('skyColorTween', 'sky', nightColor, 0.0001);
	doTweenColor('nubesColorTween', 'nubes', nightColor, 0.0001);
	doTweenColor('hillsColorTween', 'hills', nightColor, 0.0001);
doTweenColor('nubes1ColorTween', 'nubes1', nightColor, 0.0001);
doTweenColor('rockswithfarmColorTween', 'rockswithfarm', nightColor, 0.0001);
doTweenColor('rocks', 'rocks', nightColor, 0.0001);
doTweenColor('rocks2', 'rocks2', nightColor, 0.0001);

}

function postCreate(){
	doTweenColor('bfColor', 'boyfriend', nightColor, 0.0001);
	doTweenColor('gfColor', 'gf', nightColor, 0.0001);
	
}