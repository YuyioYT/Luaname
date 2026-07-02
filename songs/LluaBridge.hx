import Utils.LuaUtils;
import Sprites.ModchartSprite;
import funkin.backend.MusicBeatState;
import funkin.play.PlayState;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxObject;
import flixel.math.FlxAxes;
import flixel.util.FlxColor;
import flixel.graphics.FlxGraphic;
import Utils.CoolUtil2;
import funkin.util.Paths;
import funkin.backend.Options;

using StringTools;

///////////////// PORT BY YUYIO, CREDITS TO PSYCH ENGINE 

/////////////MAKE SPRITES FUNCTIONS
public static function makeLuaSprite(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0) {
    tag = tag.replace('.', '');
    LuaUtils.destroyObject(tag);
    var leSprite:ModchartSprite = new ModchartSprite(x, y);
    if (image != null && image.length > 0) {
        leSprite.loadGraphic(Paths.image(image));
    }
    getVariables().set(tag, leSprite);
    leSprite.active = true;
}

public static function makeAnimatedLuaSprite(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0, ?spriteType:String = 'auto') {
    tag = tag.replace('.', '');
    LuaUtils.destroyObject(tag);
    var leSprite:ModchartSprite = new ModchartSprite(x, y);

    if (image != null && image.length > 0) {
        LuaUtils.loadFrames(leSprite, image, spriteType);
    }
    getVariables().set(tag, leSprite);
}

public static function makeGraphic(obj:String, width:Int = 256, height:Int = 256, color:String = 'FFFFFF') {
    var spr:FlxSprite = LuaUtils.getObjectDirectly(obj);
    if (spr != null) spr.makeGraphic(width, height, CoolUtil2.colorFromString(color));
}

///////////////////////////////////////////////////////////


////////OBJECTS PROPERTIES 
public static function screenCenter(obj:String, pos:String = 'xy') {
    var spr:FlxObject = getLuaObject(obj);

    if (spr == null) {
        var split:Array<String> = obj.split('.');
        spr = LuaUtils.getObjectDirectly(split[0]);
        if (split.length > 1) {
            spr = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
        }
    }

    if (spr != null) {
        if (pos == null) pos = 'xy';
        switch (pos.trim().toLowerCase()) {
            case 'x':
                spr.screenCenter(FlxAxes.X);
                return;
            case 'y':
                spr.screenCenter(FlxAxes.Y);
                return;
            default:
                spr.screenCenter(FlxAxes.XY);
                return;
        }
    }
}

public static function setObjectOrder(obj:String, position:Int, ?group:String = null) {
	var leObj:FlxBasic = LuaUtils.getObjectDirectly(obj);
	if(leObj != null){
		if(group != null){
			var groupOrArray:Dynamic = Reflect.getProperty(LuaUtils.getTargetInstance(), group);
			if(groupOrArray != null){
				switch(Type.typeof(groupOrArray))	{
					case TClass(Array): //Is Array
						groupOrArray.remove(leObj);
						groupOrArray.insert(position, leObj);
					default: //Is Group
						groupOrArray.remove(leObj, true);
						groupOrArray.insert(position, leObj);
				}
			}
			//else luaTrace('setObjectOrder: Group $group doesn\'t exist!', false, false, FlxColor.RED);
	    }else{
			var groupOrArray:Dynamic = LuaUtils.getTargetInstance();
			groupOrArray.remove(leObj, true);
			groupOrArray.insert(position, leObj);
		}
		return;
	}
//	luaTrace('setObjectOrder: Object $obj doesn\'t exist!', false, false, FlxColor.RED);
}

public static function scaleObject(obj:String, x:Float, y:Float, updateHitbox:Bool = true) {
    if (getLuaObject(obj) != null) {
        var shit:FlxSprite = getLuaObject(obj);
        shit.scale.set(x, y);
        if (updateHitbox) shit.updateHitbox();
        return;
    }

    var split:Array<String> = obj.split('.');
    var poop:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
    if (split.length > 1) {
        poop = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
    }

    if (poop != null) {
        poop.scale.set(x, y);
        if (updateHitbox) poop.updateHitbox();
        return;
    }
}

public static function setGraphicSize(obj:String, x:Float, y:Float = 0, updateHitbox:Bool = true) {
	if(getLuaObject(obj)!=null) {
		var shit:FlxSprite = getLuaObject(obj);
		shit.setGraphicSize(x, y);
		if(updateHitbox) shit.updateHitbox();
		return;
	}

	var split:Array<String> = obj.split('.');
	var poop:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
	if(split.length > 1) {
		poop = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
	}

	if(poop != null) {
		poop.setGraphicSize(x, y);
		if(updateHitbox) poop.updateHitbox();
		return;
	}
			//luaTrace('setGraphicSize: Couldnt find object: ' + obj, false, false, FlxColor.RED);
}

public static function updateHitbox(obj:String) {
	if(getLuaObject(obj)!=null) {
		var shit:FlxSprite = getLuaObject(obj);
		shit.updateHitbox();
		return;
	}

	var split:Array<String> = obj.split('.');
	var poop:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
	if(split.length > 1) {
		poop = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
	}

	if(poop != null) {
		poop.updateHitbox();
		return;
	}
	//luaTrace('updateHitbox: Couldnt find object: ' + obj, false, false, FlxColor.RED);
}

public static function setScrollFactor(obj:String, scrollX:Float, scrollY:Float) {
	if(getLuaObject(obj) != null) {
		getLuaObject(obj).scrollFactor.set(scrollX, scrollY);
		return;
	}

	var object:FlxObject = Reflect.getProperty(LuaUtils.getTargetInstance(), obj);
	if(object != null) {
		object.scrollFactor.set(scrollX, scrollY);
	}
}

public static function setObjectCamera(obj:String, camera:String = 'game') {
	var real:FlxBasic = getLuaObject(obj);
	if(real != null) {
		real.cameras = [LuaUtils.cameraFromString(camera)];
		return true;
	}

	var split:Array<String> = obj.split('.');
	var object:FlxBasic = LuaUtils.getObjectDirectly(split[0]);
	if(split.length > 1) {
		object = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
	}

	if(object != null) {
		object.cameras = [LuaUtils.cameraFromString(camera)];
		return true;
	}
	//luaTrace("setObjectCamera: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
	return false;
}

public static function setBlendMode(obj:String, blend:String = '') {
	var real:FlxSprite = getLuaObject(obj);
	if(real != null) {
		real.blend = LuaUtils.blendModeFromString(blend);
		return true;
	}

	var split:Array<String> = obj.split('.');
	var spr:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
	if(split.length > 1) {
		spr = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
	}

	if(spr != null) {
		spr.blend = LuaUtils.blendModeFromString(blend);
		return true;
	}
	//luaTrace("setBlendMode: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
	return false;
}

//////////////////////////////////////////////////////

///////// ADD/REMOVE FUNCTIONS

public static function removeLuaSprite(tag:String, destroy:Bool = true, ?group:String = null) {
	var obj:FlxSprite = LuaUtils.getObjectDirectly(tag);
	if(obj == null || obj.destroy == null)
		return;
			
	var groupObj:Dynamic = null;
	if(group == null) groupObj = LuaUtils.getTargetInstance();
	else groupObj = LuaUtils.getObjectDirectly(group);

	groupObj.remove(obj, true);
    if(destroy)
	{
		getVariables().remove(tag);
		obj.destroy();
	}
}


public static function addLuaSprite(tag:String, ?inFront:Bool = false) {
    var mySprite:FlxSprite = getVariables().get(tag);
    if (mySprite == null) return;

    var instance = LuaUtils.getTargetInstance();
    if (inFront) {
        instance.add(mySprite);
    } else {
        if (PlayState.instance == null || !PlayState.instance.isDead) 
            instance.insert(instance.members.indexOf(LuaUtils.getLowestCharacterGroup()), mySprite);
		else
			GameOverSubstate.instance.insert(GameOverSubstate.instance.members.indexOf(GameOverSubstate.instance.boyfriend), mySprite);
    }
}

///////////////////////////

////////////////TWEEN FUNCTIONS

public static function startTween(tag:String, vars:String, values:Any = null, duration:Float, ?options:Any = null) {
	var penisExam:Dynamic = LuaUtils.tweenPrepare(tag, vars);
	if(penisExam != null)	{
		if(values != null){
			var myOptions:LuaTweenOptions = LuaUtils.getLuaTween(options);
			if(tag != null){
				var variables = getVariables();
				var originalTag:String = 'tween_' + LuaUtils.formatVariable(tag);
				variables.set(tag, FlxTween.tween(penisExam, values, duration, myOptions != null ? {
					type: myOptions.type,
					ease: myOptions.ease,
					startDelay: myOptions.startDelay,
					loopDelay: myOptions.loopDelay,
	
					onUpdate: function(twn:FlxTween) {
						if(myOptions.onUpdate != null) game.callOnLuas(myOptions.onUpdate, [originalTag, vars]);
					},
					onStart: function(twn:FlxTween) {
						if(myOptions.onStart != null) game.callOnLuas(myOptions.onStart, [originalTag, vars]);
					},
					onComplete: function(twn:FlxTween) {
						if(twn.type == FlxTweenType.ONESHOT || twn.type == FlxTweenType.BACKWARD) variables.remove(tag);
						if(myOptions.onComplete != null) game.callOnLuas(myOptions.onComplete, [originalTag, vars]);
					}
				} : null));
				return tag;
			}else FlxTween.tween(penisExam, values, duration, myOptions != null ? {
                type: myOptions.type,
                ease: myOptions.ease,
                startDelay: myOptions.startDelay,
                loopDelay: myOptions.loopDelay,

                onUpdate: function(twn:FlxTween) {
                    if(myOptions.onUpdate != null) game.callOnLuas(myOptions.onUpdate, [null, vars]);
                },
                onStart: function(twn:FlxTween) {
                    if(myOptions.onStart != null) game.callOnLuas(myOptions.onStart, [null, vars]);
                },
                onComplete: function(twn:FlxTween) {
                    if(myOptions.onComplete != null) game.callOnLuas(myOptions.onComplete, [null, vars]);
                }
            } : null);
		}
	//	else luaTrace('startTween: No values on 2nd argument!', false, false, FlxColor.RED);
	}
	//else luaTrace('startTween: Couldnt find object: ' + vars, false, false, FlxColor.RED);
	return null;
}

public static function onTimerCompleted(tag:String, vars:String) { trace('DOESNT WORK FOR NOW');	}

public static function onTweenCompleted(tag:String, vars:String) { trace('DOESNT WORK FOR NOW');	}

public static function doTweenX(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
	return oldTweenFunction(tag, vars, {x: value}, duration, ease, 'doTweenX');
}
public static function doTweenY(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
	return oldTweenFunction(tag, vars, {y: value}, duration, ease, 'doTweenY');
}
public static function doTweenAngle(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
	return oldTweenFunction(tag, vars, {angle: value}, duration, ease, 'doTweenAngle');
}
public static function doTweenAlpha(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
	return oldTweenFunction(tag, vars, {alpha: value}, duration, ease, 'doTweenAlpha');
}

public static function doTweenZoom(tag:String, camera:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
	switch(camera.toLowerCase()) {
		case 'camgame' | 'game': camera = 'camGame';
		case 'camhud' | 'hud': camera = 'camHUD';
		case 'camother' | 'other': camera = 'camOther';
		default:
			var cam:FlxCamera = getVariables().get(camera);
			if (cam == null || !Std.isOfType(cam, FlxCamera)) camera = 'camGame';
    }
	return oldTweenFunction(tag, camera, {zoom: value}, duration, ease, 'doTweenZoom');
}

public static function doTweenColor(tag:String, vars:String, targetColor:String, duration:Float, ?ease:String = 'linear') {
	var penisExam:Dynamic = LuaUtils.tweenPrepare(tag, vars);
	var thevars:String = vars;
	if(penisExam != null) {
		var curColor:Int = penisExam.color;
		var alphaByte:Int = Std.int(penisExam.alpha * 255);
		curColor = (curColor & 0x00FFFFFF) | (alphaByte << 24);
		if(tag != null)	{
            var originalTag:String = tag;
			tag = LuaUtils.formatVariable('tween_$tag');
			var variables = getVariables();
			variables.set(tag, FlxTween.color(penisExam, duration, curColor, CoolUtil2.colorFromString(targetColor), {ease: LuaUtils.getTweenEaseByString(ease),
				onComplete: function(twn:FlxTween)	{
					variables.remove(tag);

					onTweenCompleted(originalTag, thevars);
				}
			}));
			return tag;
		}
		else FlxTween.color(penisExam, duration, curColor, CoolUtil2.colorFromString(targetColor), {ease: LuaUtils.getTweenEaseByString(ease)});
	}
	//else luaTrace('doTweenColor: Couldnt find object: ' . vars, false, false, FlxColor.RED);
	return null;
}

public static function cancelTween(tag:String) {
	LuaUtils.cancelTween(tag);
}

public static function oldTweenFunction(tag:String, vars:String, tweenValue:Any, duration:Float, ease:String, funcName:String){
	var target:Dynamic = LuaUtils.tweenPrepare(tag, vars);
	var variables = getVariables();
	if(target != null){
		if(tag != null)	{
			var originalTag:String = tag;
			tag = LuaUtils.formatVariable('tween_$tag');
			variables.set(tag, FlxTween.tween(target, tweenValue, duration, {ease: LuaUtils.getTweenEaseByString(ease),
				onComplete: function(twn:FlxTween)	{
					variables.remove(tag);
					var thevars:String = vars;
					onTweenCompleted(originalTag, thevars);
				}
			}));
		}
		else FlxTween.tween(target, tweenValue, duration, {ease: LuaUtils.getTweenEaseByString(ease)});
		return tag;
	}
	//else luaTrace('$funcName: Couldnt find object: $vars', false, false, FlxColor.RED);
	return null;
}

////////////////////////////////

/////////////////////MOUSE FUNCTIONS
public static function mouseClicked(?button:String = 'left') {
	var click:Bool = FlxG.mouse.justPressed;
	if (button == null) button = 'left';
	switch(button.trim().toLowerCase())
	{
		case 'middle':
			click = FlxG.mouse.justPressedMiddle;
		case 'right':
			click = FlxG.mouse.justPressedRight;
	}
	return click;
}

public static function mousePressed(?button:String = 'left') {
	var press:Bool = FlxG.mouse.pressed;
	if (button == null) button = 'left';
	switch(button.trim().toLowerCase())
	{
		case 'middle':
			press = FlxG.mouse.pressedMiddle;
		case 'right':
			press = FlxG.mouse.pressedRight;
	}
	return press;
}

public static function mouseReleased(?button:String = 'left') {
	var released:Bool = FlxG.mouse.justReleased;
	if (button == null) button = 'left';
	switch(button.trim().toLowerCase())
	{
		case 'middle':
			released = FlxG.mouse.justReleasedMiddle;
		case 'right':
			released = FlxG.mouse.justReleasedRight;
	}
	return released;
}

////////////////////////////////////////////////////////////////////

///////////////////TIMER FUNCTIONS

public static function runTimer(tag:String, time:Float = 1, loops:Int = 1) {
	LuaUtils.cancelTimer(tag);
	var variables = getVariables();
			
	var originalTag:String = tag;
	tag = LuaUtils.formatVariable('timer_$tag');
	variables.set(tag, new FlxTimer().start(time, function(tmr:FlxTimer){
		if(tmr.finished) variables.remove(tag);
		onTimerCompleted(originalTag, tmr.loops, tmr.loopsLeft);
		//trace('Timer Completed: ' + tag);
	}, loops));
	return tag;
}

public static function cancelTimer(tag:String) {
	LuaUtils.cancelTimer(tag);
}

//////////////////




//////////////////////

///////////GAME FUNC
public static function addScore(value:Int = 0) {
	PlayState.instance.songScore += value;
	//game.RecalculateRating();
}

public static function addMisses(value:Int = 0) {
	PlayState.instance.misses += value;
	//game.RecalculateRating();
}

/*
public static function addHits(value:Array<Int> = []) {
	for (i in 0...value.length)
		PlayState.instance.hits += value[i];
	//game.RecalculateRating();
}*/

public static function setScore(value:Int = 0) {
	PlayState.instance.songScore = value;
	//game.RecalculateRating();
}

public static function setMisses(value:Int = 0) {
	PlayState.instance.misses = value;
	//game.RecalculateRating();
}

/*
public static function setHits(value:Int = 0) {
	PlayState.instance.hits = value;
	//game.RecalculateRating();
}*/

public static function setHealth(value:Float = 1) { PlayState.instance.health = value; }
public static function addHealth(value:Float = 0) { PlayState.instance.health += value; }
public static function getHealth() {
	return PlayState.instance.health; 
}

/////////////////////////////////////////////

///////////////////////////COLOR FUNCT
//Identical functions
public static function FlxColor(color:String) {
	return FlxColor.fromString(color); 
}
public static function getColorFromName(color:String) {
	return FlxColor.fromString(color); 
}
public static function getColorFromString(color:String) {
	return FlxColor.fromString(color); 
}
public static function getColorFromHex(color:String) {
	return FlxColor.fromString('#$color'); 
}
/*
		// precaching
		Lua_helper.add_callback(lua, "addCharacterToList", function(name:String, type:String) {
			var charType:Int = 0;
			switch(type.toLowerCase()) {
				case 'dad': charType = 1;
				case 'gf' | 'girlfriend': charType = 2;
			}
			game.addCharacterToList(name, charType);
		});
	*/
public static function precacheImage(name:String, ?allowGPU:Bool = true) {
	Paths.image(name);
	if (allowGPU)
		trace('THAT THING ITS IN OPTIONS');
}

public static function precacheSound(name:String) {
	Paths.sound(name);
}

public static function precacheMusic(name:String) {
	Paths.music(name);
}

/*		// others
		Lua_helper.add_callback(lua, "triggerEvent", function(name:String, ?value1:String = '', ?value2:String = '') {
			game.triggerEvent(name, value1, value2, Conductor.songPosition);
			//trace('Triggered event: ' + name + ', ' + value1 + ', ' + value2);
			return true;
		});

		Lua_helper.add_callback(lua, "startCountdown", function() {
			game.startCountdown();
			return true;
		});
		Lua_helper.add_callback(lua, "endSong", function() {
			game.KillNotes();
			game.endSong();
			return true;
		});
		Lua_helper.add_callback(lua, "restartSong", function(?skipTransition:Bool = false) {
			game.persistentUpdate = false;
			FlxG.camera.followLerp = 0;
			PauseSubState.restartSong(skipTransition);
			return true;
		});
		Lua_helper.add_callback(lua, "exitSong", function(?skipTransition:Bool = false) {
			if(skipTransition)
			{
				FlxTransitionableState.skipNextTransIn = true;
				FlxTransitionableState.skipNextTransOut = true;
			}

			if(PlayState.isStoryMode)
				MusicBeatState.switchState(new StoryMenuState());
			else
				MusicBeatState.switchState(new FreeplayState());

			#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			PlayState.changedDifficulty = false;
			PlayState.chartingMode = false;
			game.transitioning = true;
			FlxG.camera.followLerp = 0;
			Mods.loadTopMod();
			return true;
		});
		Lua_helper.add_callback(lua, "getSongPosition", function() {
			return Conductor.songPosition;
		});

		Lua_helper.add_callback(lua, "getCharacterX", function(type:String) {
			switch(type.toLowerCase()) {
				case 'dad' | 'opponent':
					return game.dadGroup.x;
				case 'gf' | 'girlfriend':
					return game.gfGroup.x;
				default:
					return game.boyfriendGroup.x;
			}
		});
		Lua_helper.add_callback(lua, "setCharacterX", function(type:String, value:Float) {
			switch(type.toLowerCase()) {
				case 'dad' | 'opponent':
					game.dadGroup.x = value;
				case 'gf' | 'girlfriend':
					game.gfGroup.x = value;
				default:
					game.boyfriendGroup.x = value;
			}
		});
		Lua_helper.add_callback(lua, "getCharacterY", function(type:String) {
			switch(type.toLowerCase()) {
				case 'dad' | 'opponent':
					return game.dadGroup.y;
				case 'gf' | 'girlfriend':
					return game.gfGroup.y;
				default:
					return game.boyfriendGroup.y;
			}
		});
		Lua_helper.add_callback(lua, "setCharacterY", function(type:String, value:Float) {
			switch(type.toLowerCase()) {
				case 'dad' | 'opponent':
					game.dadGroup.y = value;
				case 'gf' | 'girlfriend':
					game.gfGroup.y = value;
				default:
					game.boyfriendGroup.y = value;
			}
		});
		Lua_helper.add_callback(lua, "cameraSetTarget", function(target:String) {
			switch(target.trim().toLowerCase())
			{
				case 'gf', 'girlfriend':
					game.moveCameraToGirlfriend();
				case 'dad', 'opponent':
					game.moveCamera(true);
				default:
					game.moveCamera(false);
			}
		});
		*/

public static function setCameraScroll(x:Float, y:Float) {
	FlxG.camera.scroll.set(x - FlxG.width/2, y - FlxG.height/2);
}
public static function setCameraFollowPoint(x:Float, y:Float) {
	PlayState.instance.camFollow.setPosition(x, y);
}
public static function addCameraScroll(?x:Float = 0, ?y:Float = 0) {
	FlxG.camera.scroll.add(x, y);
}
public static function addCameraFollowPoint(?x:Float = 0, ?y:Float = 0) {
	PlayState.instance.camFollow.x += x;
	PlayState.instance.camFollow.y += y;
}
public static function getCameraScrollX() {
	return FlxG.camera.scroll.x + FlxG.width/2;
}
public static function getCameraScrollY() {
	return FlxG.camera.scroll.y + FlxG.height/2;
}
public static function getCameraFollowX() {
	return PlayState.instance.camFollow.x;
}
public static function getCameraFollowY() {
	return PlayState.instance.camFollow.y;
}
public static function cameraShake(camera:String, intensity:Float, duration:Float) {
	LuaUtils.cameraFromString(camera).shake(intensity, duration);
}

public static function cameraFlash(camera:String, color:String, duration:Float,forced:Bool) {
	LuaUtils.cameraFromString(camera).flash(CoolUtil.colorFromString(color), duration, null, forced);
}
public static function cameraFade(camera:String, color:String, duration:Float, forced:Bool, ?fadeOut:Bool = false) {
	LuaUtils.cameraFromString(camera).fade(CoolUtil.colorFromString(color), duration, fadeOut, null, forced);
}

//////////////////*
/*
function setRatingPercent(value:Float) {
			game.ratingPercent = value;
			game.setOnScripts('rating', game.ratingPercent);
		}
function setRatingName(value:String) {
			game.ratingName = value;
			game.setOnScripts('ratingName', game.ratingName);
		}
	function setRatingFC(value:String) {
			game.ratingFC = value;
			game.setOnScripts('ratingFC', game.ratingFC);
		}
		Lua_helper.add_callback(lua, "updateScoreText", function() game.updateScoreText());*/

public static function getMouseX(?camera:String = 'game') {
	var cam:FlxCamera = LuaUtils.cameraFromString(camera);
	return FlxG.mouse.getScreenPosition(cam).x;
}

public static function getMouseY(?camera:String = 'game') {
	var cam:FlxCamera = LuaUtils.cameraFromString(camera);
	return FlxG.mouse.getScreenPosition(cam).y;
}

public static function getMidpointX(variable:String) {
	var split:Array<String> = variable.split('.');
	var obj:FlxObject = LuaUtils.getObjectDirectly(split[0]);
	if(split.length > 1) {
		obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
	}
	if(obj != null) return obj.getMidpoint().x;
	return 0;
}

public static function getMidpointY(variable:String) {
	var split:Array<String> = variable.split('.');
	var obj:FlxObject = LuaUtils.getObjectDirectly(split[0]);
	if(split.length > 1) {
		obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
	}
	if(obj != null) return obj.getMidpoint().y;
	return 0;
}

public static function getGraphicMidpointX(variable:String) {
	var split:Array<String> = variable.split('.');
	var obj:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
	if(split.length > 1) {
		obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
	}
	if(obj != null) return obj.getGraphicMidpoint().x;
	return 0;
}
public static function getGraphicMidpointY(variable:String) {
	var split:Array<String> = variable.split('.');
	var obj:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
	if(split.length > 1) {
		obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);	
	}
	if(obj != null) return obj.getGraphicMidpoint().y;
	return 0;
}
public static function getScreenPositionX(variable:String, ?camera:String = 'game') {
	var split:Array<String> = variable.split('.');
	var obj:FlxObject = LuaUtils.getObjectDirectly(split[0]);
	if(split.length > 1) {
		obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);	
	}
	if(obj != null) return obj.getScreenPosition(LuaUtils.cameraFromString(camera)).x;
	return 0;
}
public static function getScreenPositionY(variable:String, ?camera:String = 'game') {
	var split:Array<String> = variable.split('.');
	var obj:FlxObject = LuaUtils.getObjectDirectly(split[0]);
	if(split.length > 1) {
		obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);	
	}
	if(obj != null) return obj.getScreenPosition(LuaUtils.cameraFromString(camera)).y;
	return 0;
}
public static function characterDance(character:String) {
	trace("WIP FOR NOW");
	/*
	switch(character.toLowerCase()) {
		case 'dad': game.dad.dance();
		case 'gf' | 'girlfriend': if(game.gf != null) game.gf.dance();
		default: game.boyfriend.dance();
	}*/
}
/*

function addAnimationByPrefix(obj:String, name:String, prefix:String, framerate:Float = 24, loop:Bool = true) {
			var obj:FlxSprite = cast LuaUtils.getObjectDirectly(obj);
			if(obj != null && obj.animation != null)
			{
				obj.animation.addByPrefix(name, prefix, framerate, loop);
				if(obj.animation.curAnim == null)
				{
					var dyn:Dynamic = cast obj;
					if(dyn.playAnim != null) dyn.playAnim(name, true);
					else dyn.animation.play(name, true);
				}
				return true;
			}
			return false;
		}

		Lua_helper.add_callback(lua, "addAnimation", function(obj:String, name:String, frames:Any, framerate:Float = 24, loop:Bool = true) {
			return LuaUtils.addAnimByIndices(obj, name, null, frames, framerate, loop);
		});

		Lua_helper.add_callback(lua, "addAnimationByIndices", function(obj:String, name:String, prefix:String, indices:Any, framerate:Float = 24, loop:Bool = false) {
			return LuaUtils.addAnimByIndices(obj, name, prefix, indices, framerate, loop);
		});

		Lua_helper.add_callback(lua, "playAnim", function(obj:String, name:String, ?forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0)
		{
			var obj:Dynamic = LuaUtils.getObjectDirectly(obj);
			if(obj.playAnim != null)
			{
				obj.playAnim(name, forced, reverse, startFrame);
				return true;
			}
			else
			{
				if(obj.anim != null) obj.anim.play(name, forced, reverse, startFrame); //FlxAnimate
				else obj.animation.play(name, forced, reverse, startFrame);
				return true;
			}
			return false;
		});
		Lua_helper.add_callback(lua, "addOffset", function(obj:String, anim:String, x:Float, y:Float) {
			var obj:Dynamic = LuaUtils.getObjectDirectly(obj);
			if(obj != null && obj.addOffset != null)
			{
				obj.addOffset(anim, x, y);
				return true;
			}
			return false;
		});
*/
public static function luaSpriteExists(tag:String) {
	var obj:FlxSprite = getVariables().get(tag);
	return (obj != null && (Std.isOfType(obj, ModchartSprite) || Std.isOfType(obj, ModchartAnimateSprite)));
}
public static function luaTextExists(tag:String) {
	var obj:FlxText = getVariables().get(tag);
	return (obj != null && Std.isOfType(obj, FlxText));
}
public static function luaSoundExists(tag:String) {
	var obj:FlxSound = getVariables().get('sound_$tag');
	return (obj != null && Std.isOfType(obj, FlxSound));
}


public static function setHealthBarColors(left:String, right:String) {
	var left_color:Null<FlxColor> = null;
	var right_color:Null<FlxColor> = null;
	if (left != null && left != '')
		left_color = CoolUtil2.colorFromString(left);
	if (right != null && right != '')
		right_color = CoolUtil2.colorFromString(right);
	if (Options.colorHealthBar) PlayState.instance.healthBar.createFilledBar(left_color,right_color);
	PlayState.instance.healthBar.updateBar();
}
public static function setTimeBarColors(left:String, right:String) {
	trace("CODENAME ENGINE DOESNT HAVE TIME BAR");
}



public static function objectsOverlap(obj1:String, obj2:String) {
	var namesArray:Array<String> = [obj1, obj2];
	var objectsArray:Array<FlxBasic> = [];
	for (i in 0...namesArray.length)
	{
		var real:FlxBasic = game.getLuaObject(namesArray[i]);
		if(real != null)
			objectsArray.push(real);
		else
			objectsArray.push(Reflect.getProperty(LuaUtils.getTargetInstance(), namesArray[i]));
	}
	return (!objectsArray.contains(null) && FlxG.overlap(objectsArray[0], objectsArray[1]));
}

public static function getPixelColor(obj:String, x:Int, y:Int) {
	var split:Array<String> = obj.split('.');
	var spr:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
	if(split.length > 1) {
		spr = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
	}

	if(spr != null) return spr.pixels.getPixel32(x, y);
	return FlxColor.BLACK;
}
