package lua;

import funkin.game.PlayState;
import funkin.game.Character;
import funkin.game.cutscenes.VideoCutscene;

import funkin.backend.assets.Paths;

import funkin.backend.system.Conductor;
import funkin.backend.system.Logs;
import funkin.backend.utils.NdllUtil;
import funkin.backend.FunkinSprite;

import funkin.backend.scripting.Script;
import funkin.backend.shaders.CustomShader;

import funkin.options.Options;

import openfl.utils.Assets;

import flixel.util.FlxSave;

import flixel.input.gamepad.FlxGamepadInputID;

import haxe.ds.StringMap;

import sys.FileSystem;
import sys.io.File;

import Utils.LuaUtils;
import Utils.LuaTweenOptions;
import Utils.CoolUtil2;

import Sprites.ModchartSprite;
import Sprites.ModchartAnimateSprite;

using StringTools;

class FunkinLua {

	public var scriptName:String = '';
	public var modFolder:String = null;
	public var closed:Bool = false;

	public static var customFunctions:StringMap<Dynamic> = new StringMap<Dynamic>();
	public static var all:Array<FunkinLua> = [];
	public static var current:FunkinLua = null;

	public static var Function_Stop:String = "##PSYCHLUA_FUNCTIONSTOP";
	public static var Function_Continue:String = "##PSYCHLUA_FUNCTIONCONTINUE";
	public static var Function_StopLua:String = "##PSYCHLUA_FUNCTIONSTOPLUA";
	public static var Function_StopHScript:String = "##PSYCHLUA_FUNCTIONSTOPHSCRIPT";
	public static var Function_StopAll:String = "##PSYCHLUA_FUNCTIONSTOPALL";

	static var _variables:StringMap<Dynamic> = new StringMap<Dynamic>();
	public static function getVariables():StringMap<Dynamic> { return _variables; }

	var L:Dynamic = null;      
	var callbacks:StringMap<Dynamic> = new StringMap<Dynamic>();

	static var handlersReady:Bool = false;

	static function luaPrint(text:String):Void {
		trace('[Lua] ' + text);
		try {
			if (PlayState.instance != null && PlayState.instance.scripts != null)
				PlayState.instance.scripts.call('addTextToDebug', [text, FlxColor.WHITE]);
		} catch (e:Dynamic) {}
	}

	static function callbackHandler(state:Dynamic, name:String):Int {
		var self:FunkinLua = null;
		for (s in all) if (s.L == state) { self = s; break; }
		if (self == null) self = current;
		if (self == null) return 0;

		var fn:Dynamic = self.callbacks.get(name);
		if (fn == null) return 0;

		var args:Array<Dynamic> = [];
		var n:Int = Lj.gettop(state);
		for (i in 1...n + 1) args.push(Lj.readValue(state, i));

		var ret:Dynamic = null;
		try {
			ret = Reflect.callMethod(null, fn, args);
		} catch (e:Dynamic) {
			Logs.error('[Lua] Callback "$name" (${self.scriptName}): ${Std.string(e)}');
			return 0;
		}
		if (ret == null) return 0;
		Lj.pushValue(state, ret);
		return 1;
	}

	function addCallback(name:String, fn:Dynamic):Void {
		callbacks.set(name, fn);
		Lj.addCallbackFunction(L, name);
	}

	public function new(scriptName:String) {
		this.scriptName = scriptName.trim();

		var parts:Array<String> = this.scriptName.replace('\\', '/').split('/');
		var mi:Int = parts.indexOf('mods');
		if (mi >= 0 && parts.length > mi + 1) this.modFolder = parts[mi + 1];

		Lj.init();
		if (!handlersReady) {
			handlersReady = true;
			Lj.setCallbacksFunction(callbackHandler);
			Lj.registerHxtraceFunc(luaPrint);
		}

		L = Lj.newstate();
		if (L == null) {
			Logs.error('[Lua] ERROR CREATING LUA STATE');
			closed = true;
			return;
		}
		all.push(this);

		Lj.openlibs(L);             
		Lj.registerHxtraceLib(L);   

		Lj.setGlobal(L, 'Function_Stop', Function_Stop);
		Lj.setGlobal(L, 'Function_Continue', Function_Continue);
		Lj.setGlobal(L, 'Function_StopLua', Function_StopLua);
		Lj.setGlobal(L, 'Function_StopHScript', Function_StopHScript);
		Lj.setGlobal(L, 'Function_StopAll', Function_StopAll);
		Lj.setGlobal(L, 'scriptName', this.scriptName);
		Lj.setGlobal(L, 'curStep', 0);
		Lj.setGlobal(L, 'curBeat', 0);
		setGlobals();

		for (name => func in customFunctions)
			if (func != null) addCallback(name, func);

		addCallback("debugPrint", function(?text:Dynamic = '', ?color:String = 'WHITE') {
			if (color == null || color == '') color = 'WHITE';
			var str:String = Std.string(text);
			Logs.infos('[Lua] ' + str);
			try {
				PlayState.instance.scripts.call('addTextToDebug', [str, CoolUtil2.colorFromString(color)]);
			} catch (e:Dynamic) {}
		});

		addCallback("makeLuaSprite", function(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0) {
			tag = tag.replace('.', '');
			LuaUtils.destroyObject(tag);
			var leSprite:ModchartSprite = new ModchartSprite(x, y);
			leSprite.active = true;
			getVariables().set(tag, leSprite);
			if (image != null && image.length > 0) {
				try {
					var path:String = Paths.image(image);
					if (Assets.exists(path)) leSprite.loadGraphic(path);
					else luaTrace('makeLuaSprite: image ' + image + ' not found (sprite created without graphic)', false, false, FlxColor.YELLOW);
				} catch (e:Dynamic) {
					luaTrace('makeLuaSprite: could not load ' + image + ': ' + Std.string(e), false, false, FlxColor.YELLOW);
				}
			}
		});

		addCallback("makeAnimatedLuaSprite", function(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0, ?spriteType:String = 'auto') {
			tag = tag.replace('.', '');
			LuaUtils.destroyObject(tag);
			var leSprite:ModchartSprite = new ModchartSprite(x, y);
			getVariables().set(tag, leSprite);
			if (image != null && image.length > 0) {
				try {
					LuaUtils.loadFrames(leSprite, image, spriteType);
				} catch (e:Dynamic) {
					luaTrace('makeAnimatedLuaSprite: could not load ' + image + ': ' + Std.string(e), false, false, FlxColor.YELLOW);
				}
			}
		});

		addCallback("makeGraphic", function(obj:String, width:Int = 256, height:Int = 256, color:String = 'FFFFFF') {
			var spr:FlxSprite = resolveObject(obj);
			if (spr != null) spr.makeGraphic(width, height, CoolUtil2.colorFromString(color));
		});

		addCallback("addAnimationByPrefix", function(obj:String, name:String, prefix:String, framerate:Float = 24, loop:Bool = true) {
			var obj:FlxSprite = cast resolveObject(obj);
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
		});

		addCallback("addAnimationByIndices", function(obj:String, name:String, prefix:String, indices:Any, framerate:Float = 24, loop:Bool = false) {
			return LuaUtils.addAnimByIndices(obj, name, prefix, indices, framerate, loop);
		});

		addCallback("playAnim", function(obj:String, name:String, ?forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0) {
			var o:Dynamic = getLuaObject(obj);
			if (o == null) o = resolveObject(obj);
			if (o == null) {
				luaTrace('playAnim: Object ' + obj + ' doesn\'t exist!', false, false, FlxColor.RED);
				return false;
			}
			if (Std.isOfType(o, FunkinSprite)) {
				var fs:FunkinSprite = cast o;
				if (!fs.hasAnim(name)) {
					luaTrace('playAnim: Animation ' + name + ' doesn\'t exist on ' + obj + '!', false, false, FlxColor.RED);
					return false;
				}
				fs.playAnim(name, forced, null, reverse, startFrame);
				return true;
			}
			var anim:Dynamic = o.animation;
			if (anim != null) {
				anim.play(name, forced, reverse, startFrame);
				return true;
			}
			return false;
		});

		/////////OBJECTS PROPERTIES 
		addCallback("screenCenter", function(obj:String, pos:String = 'xy') {
			var spr:FlxObject = getLuaObject(obj);

			if (spr == null) {
				var split:Array<String> = obj.split('.');
				spr = resolveObject(split[0]);
				if (split.length > 1) {
					spr = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
				}
			}

			if (spr != null) {
				if (pos == null) pos = 'xy';
				switch (pos.trim().toLowerCase()) {
					case 'x':
						spr.screenCenter(0x01);
						return;
					case 'y':
						spr.screenCenter(0x10);
						return;
					default:
						spr.screenCenter(0x11);
						return;
				}
			}
		});

		addCallback("setObjectOrder", function(obj:String, position:Int, ?group:String = null) {
			var leObj:Dynamic = getLuaObject(obj);
			if (leObj == null) leObj = resolveObject(obj);
			if (leObj != null) {
				var groupObj:Dynamic = null;
				if (group != null) {
					groupObj = getProperty(group);
					if (groupObj == null) {
						luaTrace('setObjectOrder: Group $group doesn\'t exist!');
						return;
					}
				} else groupObj = LuaUtils.getTargetInstance();

				if (Std.isOfType(groupObj, Array)) {
					groupObj.remove(leObj);
					groupObj.insert(position, leObj);
				} else {
					groupObj.remove(leObj, true);
					groupObj.insert(position, leObj);
				}
				return;
			}
			luaTrace('setObjectOrder: Object $obj doesn\'t exist!');
		});

		addCallback("scaleObject", function(obj:String, x:Float, y:Float, updateHitbox:Bool = true) {
			if (getLuaObject(obj) != null) {
				var shit:FlxSprite = getLuaObject(obj);
				shit.scale.set(x, y);
				if (updateHitbox) shit.updateHitbox();
				return;
			}

			var split:Array<String> = obj.split('.');
			var poop:FlxSprite = resolveObject(split[0]);
			if (split.length > 1) {
				poop = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
			}

			if (poop != null) {
				poop.scale.set(x, y);
				if (updateHitbox) poop.updateHitbox();
				return;
			}
		});

		addCallback("setGraphicSize", function(obj:String, x:Float, y:Float = 0, updateHitbox:Bool = true) {
			if(getLuaObject(obj)!=null) {
				var shit:FlxSprite = getLuaObject(obj);
				shit.setGraphicSize(x, y);
				if(updateHitbox) shit.updateHitbox();
				return;
			}

			var split:Array<String> = obj.split('.');
			var poop:FlxSprite = resolveObject(split[0]);
			if(split.length > 1) {
				poop = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(poop != null) {
				poop.setGraphicSize(x, y);
				if(updateHitbox) poop.updateHitbox();
				return;
			}
			luaTrace('setGraphicSize: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});

		addCallback("updateHitbox", function(obj:String) {
			if(getLuaObject(obj)!=null) {
				var shit:FlxSprite = getLuaObject(obj);
				shit.updateHitbox();
				return;
			}

			var split:Array<String> = obj.split('.');
			var poop:FlxSprite = resolveObject(split[0]);
			if(split.length > 1) {
				poop = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(poop != null) {
				poop.updateHitbox();
				return;
			}
			luaTrace('updateHitbox: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});

		addCallback("setScrollFactor", function(obj:String, scrollX:Float, scrollY:Float) {
			if(getLuaObject(obj) != null) {
				getLuaObject(obj).scrollFactor.set(scrollX, scrollY);
				return;
			}

			var object:FlxObject = Reflect.getProperty(LuaUtils.getTargetInstance(), obj);
			if(object != null) {
				object.scrollFactor.set(scrollX, scrollY);
			}
		});

		addCallback("setObjectCamera", function(obj:String, camera:String = 'game') {
			var real:FlxBasic = getLuaObject(obj);
			if(real != null) {
				real.cameras = [LuaUtils.cameraFromString(camera)];
				return true;
			}

			var split:Array<String> = obj.split('.');
			var object:FlxBasic = resolveObject(split[0]);
			if(split.length > 1) {
				object = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(object != null) {
				object.cameras = [LuaUtils.cameraFromString(camera)];
				return true;
			}
			luaTrace("setObjectCamera: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});

		addCallback("setBlendMode", function(obj:String, blend:String = '') {
			var real:FlxSprite = getLuaObject(obj);
			if(real != null) {
				real.blend = LuaUtils.blendModeFromString(blend);
				return true;
			}

			var split:Array<String> = obj.split('.');
			var spr:FlxSprite = resolveObject(split[0]);
			if(split.length > 1) {
				spr = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(spr != null) {
				spr.blend = LuaUtils.blendModeFromString(blend);
				return true;
			}
			luaTrace("setBlendMode: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});

		///////////ADD/REMOVE
		addCallback("removeLuaSprite", function(tag:String, destroy:Bool = true, ?group:String = null) {
			var obj:FlxSprite = resolveObject(tag);
			if(obj == null || obj.destroy == null)
				return;
					
			var groupObj:Dynamic = null;
			if(group == null) groupObj = LuaUtils.getTargetInstance();
			else groupObj = resolveObject(group);

			groupObj.remove(obj, true);
			if(destroy)
			{
				getVariables().remove(tag);
				obj.destroy();
			}
		});

		addCallback("addLuaSprite", function(tag:String, ?inFront:Bool = false) {
			var mySprite:FlxSprite = getVariables().get(tag);
			if (mySprite == null) return;

			var instance:Dynamic = LuaUtils.getTargetInstance();
			if (inFront) {
				instance.add(mySprite);
				return;
			}
			var idx:Int = lowestCharacterIndex(instance);
			if (idx < 0) instance.add(mySprite);
			else instance.insert(idx, mySprite);
		});

		////////////////////TWEEN
		addCallback("startTween", function(tag:String, vars:String, values:Dynamic, duration:Float, ?options:Dynamic = null) {
			var target:Dynamic = tweenPrepare(tag, vars);
			if (target == null) {
				luaTrace('startTween: Couldnt find object: ' + vars, false, false, FlxColor.RED);
				return null;
			}
			if (values == null) {
				luaTrace('startTween: No values on 2nd argument!', false, false, FlxColor.RED);
				return null;
			}

			var getOpt:String->Dynamic = function(name:String):Dynamic {
				return (options != null && Reflect.hasField(options, name)) ? Reflect.field(options, name) : null;
			};
			var twnType:FlxTweenType = tweenTypeFromString(getOpt('type'));
			var easeName:String = getOpt('ease');
			var startDelay:Float = 0;
			var loopDelay:Float = 0;
			var sd:Dynamic = getOpt('startDelay');
			if (sd != null) startDelay = sd;
			var ld:Dynamic = getOpt('loopDelay');
			if (ld != null) loopDelay = ld;
			var onUpdateName:String = getOpt('onUpdate');
			var onStartName:String = getOpt('onStart');
			var onCompleteName:String = getOpt('onComplete');

			var originalTag:String = tag;
			var variables = getVariables();
			var key:String = null;
			if (tag != null) key = LuaUtils.formatVariable('tween_' + tag);

			var tw:FlxTween = FlxTween.tween(target, values, duration, {
				type: twnType,
				ease: LuaUtils.getTweenEaseByString(easeName == null ? 'linear' : easeName),
				startDelay: startDelay,
				loopDelay: loopDelay,
				onUpdate: function(twn:FlxTween) {
					if (onUpdateName != null) callOnAll(onUpdateName, [originalTag, vars]);
				},
				onStart: function(twn:FlxTween) {
					if (onStartName != null) callOnAll(onStartName, [originalTag, vars]);
				},
				onComplete: function(twn:FlxTween) {
					if (key != null && (twn.type == 8 || twn.type == 16)) variables.remove(key);
					if (onCompleteName != null) callOnAll(onCompleteName, [originalTag, vars]);
				}
			});
			if (key != null) {
				variables.set(key, tw);
				return key;
			}
			return null;
		});

		addCallback("doTweenX", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return oldTweenFunction(tag, vars, {x: value}, duration, ease, 'doTweenX');
		});

		addCallback("doTweenY", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return oldTweenFunction(tag, vars, {y: value}, duration, ease, 'doTweenY');
		});

		addCallback("doTweenAngle", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return oldTweenFunction(tag, vars, {angle: value}, duration, ease, 'doTweenAngle');
		});

		addCallback("doTweenAlpha", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return oldTweenFunction(tag, vars, {alpha: value}, duration, ease, 'doTweenAlpha');
		});

		addCallback("doTweenZoom", function(tag:String, camera:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			var camKey:String = camera;
			switch (camera.toLowerCase()) {
				case 'camgame' | 'game':
					camKey = 'camGame';
				case 'camhud' | 'hud':
					camKey = 'camHUD';
				case 'camother' | 'other':
					// Codename has no camOther: use the top-most camera instead
					camKey = 'camOther';
					if (getVariables().get('camOther') == null)
						getVariables().set('camOther', FlxG.cameras.list[FlxG.cameras.list.length - 1]);
				default:
					var cam:FlxCamera = getVariables().get(camera);
					if (cam == null || !Std.isOfType(cam, FlxCamera)) camKey = 'camGame';
			}
			return oldTweenFunction(tag, camKey, {zoom: value}, duration, ease, 'doTweenZoom');
		});

		addCallback("doTweenColor", function(tag:String, vars:String, targetColor:String, duration:Float, ?ease:String = 'linear') {
			var penisExam:Dynamic = tweenPrepare(tag, vars);
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
		else luaTrace('doTweenColor: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			return null;
		});

		addCallback("cancelTween", function(tag:String) {
			LuaUtils.cancelTween(tag);
		});

		////////////////////////MOUSE
		addCallback("mouseClicked", function(?button:String = 'left') {
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
		});

		addCallback("mousePressed", function(?button:String = 'left') {
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
		});

		addCallback("mouseReleased", function(?button:String = 'left') {
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
		});

		////////////////////////TIMER
		addCallback("runTimer", function(tag:String, time:Float = 1, loops:Int = 1) {
			LuaUtils.cancelTimer(tag);
			var variables = getVariables();
					
			var originalTag:String = tag;
			tag = LuaUtils.formatVariable('timer_$tag');
			variables.set(tag, new FlxTimer().start(time, function(tmr:FlxTimer){
				if(tmr.finished) variables.remove(tag);
				onTimerCompleted(originalTag, tmr.loops, tmr.loopsLeft);
				//trace('Timer Completed: ' . tag);
			}, loops));
			return tag;
		});

		addCallback("cancelTimer", function(tag:String) {
			LuaUtils.cancelTimer(tag);
		});

		//////////Playstate
		addCallback("addScore", function(value:Int = 0) {
			PlayState.instance.songScore += value;
			//game.RecalculateRating();
		});

		addCallback("addMisses", function(value:Int = 0) {
			PlayState.instance.misses += value;
			refreshRating();
		});

		/*
		public static function addHits(value:Array<Int> = []) {
			for (i in 0...value.length)
				PlayState.instance.hits += value[i];
			//game.RecalculateRating();
		}*/
		addCallback("setScore", function(value:Int = 0) {
			PlayState.instance.songScore = value;
			//game.RecalculateRating();
		});

		addCallback("setMisses", function(value:Int = 0) {
			PlayState.instance.misses = value;
			refreshRating();
		});
		addCallback("setHealth", function(value:Float = 1) { PlayState.instance.health = value; });

		addCallback("addHealth", function(value:Float = 0) { PlayState.instance.health += value; });

		addCallback("getHealth", function() {
			return PlayState.instance.health; 
		});

		addCallback("FlxColor", function(color:String) {
			return FlxColor.fromString(color); 
		});

		addCallback("getColorFromName", function(color:String) {
			return FlxColor.fromString(color); 
		});

		addCallback("getColorFromString", function(color:String) {
			return FlxColor.fromString(color); 
		});

		addCallback("getColorFromHex", function(color:String) {
			return FlxColor.fromString('#$color'); 
		});

		addCallback("precacheImage", function(name:String, ?allowGPU:Bool = true) {
			try {
				FlxG.bitmap.add(Paths.image(name));
			} catch (e:Dynamic) {
				luaTrace('precacheImage: ' + Std.string(e));
			}
		});

		addCallback("precacheSound", function(name:String) {
			try {
				Assets.getSound(Paths.sound(name));
			} catch (e:Dynamic) {
				luaTrace('precacheSound: ' + Std.string(e));
			}
		});

		addCallback("precacheMusic", function(name:String) {
			try {
				Assets.getSound(Paths.music(name));
			} catch (e:Dynamic) {
				luaTrace('precacheMusic: ' + Std.string(e));
			}
		});

		addCallback("setCameraScroll", function(x:Float, y:Float) {
			FlxG.camera.scroll.set(x - FlxG.width/2, y - FlxG.height/2);
		});

		addCallback("setCameraFollowPoint", function(x:Float, y:Float) {
			PlayState.instance.camFollow.setPosition(x, y);
		});

		addCallback("addCameraScroll", function(?x:Float = 0, ?y:Float = 0) {
			FlxG.camera.scroll.add(x, y);
		});

		addCallback("addCameraFollowPoint", function(?x:Float = 0, ?y:Float = 0) {
			PlayState.instance.camFollow.x += x;
			PlayState.instance.camFollow.y += y;
		});

		addCallback("getCameraScrollX", function() {
			return FlxG.camera.scroll.x + FlxG.width/2;
		});

		addCallback("getCameraScrollY", function() {
			return FlxG.camera.scroll.y + FlxG.height/2;
		});

		addCallback("getCameraFollowX", function() {
			return PlayState.instance.camFollow.x;
		});

		addCallback("getCameraFollowY", function() {
			return PlayState.instance.camFollow.y;
		});

		addCallback("cameraShake", function(camera:String, intensity:Float, duration:Float) {
			LuaUtils.cameraFromString(camera).shake(intensity, duration);
		});

		addCallback("cameraFlash", function(camera:String, color:String, duration:Float, ?forced:Bool = false) {
			LuaUtils.cameraFromString(camera).flash(CoolUtil2.colorFromString(color), duration, null, forced);
		});

		addCallback("cameraFade", function(camera:String, color:String, duration:Float, ?forced:Bool = false, ?fadeOut:Bool = false) {
			LuaUtils.cameraFromString(camera).fade(CoolUtil2.colorFromString(color), duration, fadeOut, null, forced);
		});

		//////////////////
		addCallback("getMouseX", function(?camera:String = 'game') {
			var cam:FlxCamera = LuaUtils.cameraFromString(camera);
			return FlxG.mouse.getScreenPosition(cam).x;
		});

		addCallback("getMouseY", function(?camera:String = 'game') {
			var cam:FlxCamera = LuaUtils.cameraFromString(camera);
			return FlxG.mouse.getScreenPosition(cam).y;
		});

		addCallback("getMidpointX", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = resolveObject(split[0]);
			if(split.length > 1) {
				obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return obj.getMidpoint().x;
			return 0;
		});

		addCallback("getMidpointY", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = resolveObject(split[0]);
			if(split.length > 1) {
				obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return obj.getMidpoint().y;
			return 0;
		});

		addCallback("getGraphicMidpointX", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxSprite = resolveObject(split[0]);
			if(split.length > 1) {
				obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return obj.getGraphicMidpoint().x;
			return 0;
		});

		addCallback("getGraphicMidpointY", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxSprite = resolveObject(split[0]);
			if(split.length > 1) {
				obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);	
			}
			if(obj != null) return obj.getGraphicMidpoint().y;
			return 0;
		});

		addCallback("getScreenPositionX", function(variable:String, ?camera:String = 'game') {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = resolveObject(split[0]);
			if(split.length > 1) {
				obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);	
			}
			if(obj != null) return obj.getScreenPosition(LuaUtils.cameraFromString(camera)).x;
			return 0;
		});

		addCallback("getScreenPositionY", function(variable:String, ?camera:String = 'game') {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = resolveObject(split[0]);
			if(split.length > 1) {
				obj = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);	
			}
			if(obj != null) return obj.getScreenPosition(LuaUtils.cameraFromString(camera)).y;
			return 0;
		});

		addCallback("characterDance", function(character:String) {
			var c:Dynamic = getChar(character);
			if (c != null && Std.isOfType(c, Character)) {
				var ch:Character = cast c;
				ch.dance();
			}
		});

		addCallback("luaSpriteExists", function(tag:String) {
			var obj:Dynamic = getVariables().get(tag);
			if (obj == null) return false;
			if (Std.isOfType(obj, FlxText)) return false;
			var cn:String = Type.getClassName(Type.getClass(obj));
			return (cn != null && cn.indexOf('Modchart') >= 0 && cn.indexOf('Sprite') >= 0) || Std.isOfType(obj, FlxSprite);
		});

		addCallback("luaTextExists", function(tag:String) {
			var obj:FlxText = getVariables().get(tag);
			return (obj != null && Std.isOfType(obj, FlxText));
		});

		addCallback("luaSoundExists", function(tag:String) {
			var obj:FlxSound = getVariables().get('sound_$tag');
			return (obj != null && Std.isOfType(obj, FlxSound));
		});

		addCallback("setHealthBarColors", function(left:String, right:String) {
			var g:PlayState = PlayState.instance;
			if (g == null || g.healthBar == null) return;
			var leftColor:FlxColor = (g.dad != null && g.dad.iconColor != null) ? g.dad.iconColor : (PlayState.opponentMode ? 0xFF66FF33 : 0xFFFF0000);
			var rightColor:FlxColor = (g.boyfriend != null && g.boyfriend.iconColor != null) ? g.boyfriend.iconColor : (PlayState.opponentMode ? 0xFFFF0000 : 0xFF66FF33);
			if (left != null && left != '') leftColor = CoolUtil2.colorFromString(left);
			if (right != null && right != '') rightColor = CoolUtil2.colorFromString(right);
			if (Options.colorHealthBar) {
				g.healthBar.createFilledBar(leftColor, rightColor);
				g.healthBar.updateBar();
			}
		});

		addCallback("setTimeBarColors", function(left:String, right:String) {
			trace("CODENAME ENGINE DOESNT HAVE TIME BAR");
		});

		addCallback("objectsOverlap", function(obj1:String, obj2:String) {
			var namesArray:Array<String> = [obj1, obj2];
			var objectsArray:Array<FlxBasic> = [];
			for (i in 0...namesArray.length)
			{
				var real:FlxBasic = getLuaObject(namesArray[i]);
				if(real != null)
					objectsArray.push(real);
				else
					objectsArray.push(Reflect.getProperty(LuaUtils.getTargetInstance(), namesArray[i]));
			}
			return (!objectsArray.contains(null) && FlxG.overlap(objectsArray[0], objectsArray[1]));
		});

		addCallback("getPixelColor", function(obj:String, x:Int, y:Int) {
			var split:Array<String> = obj.split('.');
			var spr:FlxSprite = resolveObject(split[0]);
			if(split.length > 1) {
				spr = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(spr != null) return spr.pixels.getPixel32(x, y);
			return FlxColor.BLACK;
		});


		////////////////sound
		addCallback("playMusic", function(sound:String, ?volume:Float = 1, ?loop:Bool = false) {
				FlxG.sound.playMusic(Paths.music(sound), volume, loop);
			});

		addCallback("playSound", function(sound:String, ?volume:Float = 1, ?tag:String = null, ?loop:Bool = false) {
				if(tag != null && tag.length > 0)
				{
					var originalTag:String = tag;
					tag = LuaUtils.formatVariable('sound_$tag');
					var variables = getVariables();
					var oldSnd = variables.get(tag);
					if(oldSnd != null)
					{
						oldSnd.stop();
						oldSnd.destroy();
					}
					
					var looped:Bool = loop;

					variables.set(tag, FlxG.sound.play(Paths.sound(sound), volume, loop, null, true, function()
					{
						if(!looped) variables.remove(tag);
						onSoundFinished(originalTag);
					}));
					return tag;
				}
				FlxG.sound.play(Paths.sound(sound), volume);
				return null;
			});

		addCallback("stopSound", function(tag:String) {
				if(tag == null || tag.length < 1)
				{
					if(FlxG.sound.music != null)
						FlxG.sound.music.stop();
				}
				else
				{
					tag = LuaUtils.formatVariable('sound_$tag');
					var variables = getVariables();
					var snd:FlxSound = variables.get(tag);
					if(snd != null)
					{
						snd.stop();
						variables.remove(tag);
					}
				}
			});

		addCallback("pauseSound", function(tag:String) {
				if(tag == null || tag.length < 1)
				{
					if(FlxG.sound.music != null)
						FlxG.sound.music.pause();
				}
				else
				{
					tag = LuaUtils.formatVariable('sound_$tag');
					var snd:FlxSound = getVariables().get(tag);
					if(snd != null) snd.pause();
				}
			});

		addCallback("resumeSound", function(tag:String) {
			if (tag == null || tag.length < 1) {
				if (FlxG.sound.music != null) FlxG.sound.music.resume();
			} else {
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = getVariables().get(tag);
				if (snd != null) snd.resume();
			}
		});

		addCallback("soundFadeIn", function(tag:String, duration:Float, fromValue:Float = 0, toValue:Float = 1) {
				if(tag == null || tag.length < 1)
				{
					if(FlxG.sound.music != null)
						FlxG.sound.music.fadeIn(duration, fromValue, toValue);
				}
				else
				{
					tag = LuaUtils.formatVariable('sound_$tag');
					var snd:FlxSound = getVariables().get(tag);
					if(snd != null)
						snd.fadeIn(duration, fromValue, toValue);
				}
			});
		addCallback("setSoundVolume", function(tag:String, value:Float) {
				if(tag == null || tag.length < 1)
				{
					tag = LuaUtils.formatVariable('sound_$tag');
					if(FlxG.sound.music != null)
					{
						FlxG.sound.music.volume = value;
						return;
					}
				}
				else
				{
					tag = LuaUtils.formatVariable('sound_$tag');
					var snd:FlxSound = getVariables().get(tag);
					if(snd != null) snd.volume = value;
				}
			});


		///////////////////// Save data
		addCallback("initSaveData", function(name:String, ?folder:String = 'psychenginemods') {
			var variables = getVariables();
			if(!variables.exists('save_$name'))
			{
				var save:FlxSave = new FlxSave();
				// folder goes unused for flixel 5 users. @BeastlyGhost
				save.bind(name, CoolUtil2.getSavePath() + '/' + folder);
				variables.set('save_$name', save);
				return;
			}
			trace('initSaveData: Save file already initialized: ' + name);
		});

		addCallback("flushSaveData", function(name:String) {
			var variables = getVariables();
			if(variables.exists('save_$name'))
			{
				variables.get('save_$name').flush();
				return;
			}
			trace('flushSaveData: Save file not initialized: ' + name);
		});

		addCallback("getDataFromSave", function(name:String, field:String, ?defaultValue:Dynamic = null) {
			var variables = getVariables();
			if(variables.exists('save_$name'))
			{
				var saveData = variables.get('save_$name').data;
				if(Reflect.hasField(saveData, field))
					return Reflect.field(saveData, field);
				else
					return defaultValue;
			}
			trace('getDataFromSave: Save file not initialized: ' + name);
			return defaultValue;
		});

		addCallback("setDataFromSave", function(name:String, field:String, value:Dynamic) {
			var variables = getVariables();
			if(variables.exists('save_$name'))
			{
				Reflect.setField(variables.get('save_$name').data, field, value);
				return;
			}
			trace('setDataFromSave: Save file not initialized: ' + name);
		});

		addCallback("getProperty", function(variable:String, ?allowMaps:Bool = false) {
			return getProperty(variable, allowMaps);
		});

		addCallback("setProperty", function(variable:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false) {
			setProperty(variable, value, allowMaps, allowInstances);
		});

		addCallback("getPropertyFromClass", function(classVar:String, variable:String, ?allowMaps:Bool = false) {
			var myClass:Dynamic = resolveClassByName(classVar);
			if (myClass == null) {
				luaTrace('getPropertyFromClass: Class ' + classVar + ' not found');
				return null;
			}
			return getPath(myClass, variable, allowMaps);
		});

		addCallback("setPropertyFromClass", function(classVar:String, variable:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false) {
			var myClass:Dynamic = resolveClassByName(classVar);
			if (myClass == null) {
				luaTrace('setPropertyFromClass: Class ' + classVar + ' not found');
				return;
			}
			setPath(myClass, variable, parseInstance(value, allowInstances), allowMaps);
		});

		addCallback("getPropertyFromGroup", function(group:String, index:Int, variable:String, ?allowMaps:Bool = false) {
			var obj:Dynamic = groupMember(group, index);
			if (obj == null) return null;
			return getPath(obj, variable, allowMaps);
		});

		addCallback("setPropertyFromGroup", function(group:String, index:Int, variable:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false) {
			var obj:Dynamic = groupMember(group, index);
			if (obj == null) return;
			setPath(obj, variable, parseInstance(value, allowInstances), allowMaps);
		});

		///////// SCRIPTS
		addCallback("getRunningScripts", function() {
			var r:Array<String> = [];
			for (s in all) r.push(s.scriptName);
			return r;
		});

		addCallback("setOnScripts", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null) {
			setOnAll(varName, arg, withSelf(exclusions, ignoreSelf));
			try PlayState.instance.scripts.set(varName, arg) catch (e:Dynamic) {}
		});
		addCallback("setOnLuas", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null) {
			setOnAll(varName, arg, withSelf(exclusions, ignoreSelf));
		});
		addCallback("setOnHScript", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null) {
			try PlayState.instance.scripts.set(varName, arg) catch (e:Dynamic) {}
		});

		addCallback("callOnLuas", function(funcName:String, ?args:Array<Dynamic> = null, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String> = null, ?excludeValues:Array<Dynamic> = null) {
			return callOnAll(funcName, args, ignoreStops, withSelf(excludeScripts, ignoreSelf), excludeValues);
		});
		addCallback("callOnScripts", function(funcName:String, ?args:Array<Dynamic> = null, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String> = null, ?excludeValues:Array<Dynamic> = null) {
			if (args == null) args = [];
			if (excludeValues == null) excludeValues = [Function_Continue];
			var r:Dynamic = callOnAll(funcName, args, ignoreStops, withSelf(excludeScripts, ignoreSelf), excludeValues);
			if (r == null || excludeValues.contains(r)) {
				try r = PlayState.instance.scripts.call(funcName, args) catch (e:Dynamic) {}
			}
			return r;
		});
		addCallback("callOnHScript", function(funcName:String, ?args:Array<Dynamic> = null, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String> = null, ?excludeValues:Array<Dynamic> = null) {
			if (args == null) args = [];
			try return PlayState.instance.scripts.call(funcName, args) catch (e:Dynamic) {}
			return null;
		});

		addCallback("callScript", function(luaFile:String, funcName:String, ?args:Array<Dynamic> = null) {
			var path:String = findScript(luaFile);
			if (path != null)
				for (s in all)
					if (s.scriptName == path) return s.call(funcName, args == null ? [] : args);
			return null;
		});

		addCallback("isRunning", function(scriptFile:String) {
			var path:String = findScript(scriptFile);
			if (path != null)
				for (s in all)
					if (s.scriptName == path) return true;
			var hpath:String = findScript(scriptFile, '.hx');
			if (hpath != null) {
				try {
					for (s in PlayState.instance.scripts.scripts)
						if (s.path == hpath) return true;
				} catch (e:Dynamic) {}
			}
			return false;
		});

		addCallback("addLuaScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false) {
			var path:String = findScript(luaFile);
			if (path == null) { luaTrace("addLuaScript: Script doesn't exist!"); return; }
			if (!ignoreAlreadyRunning)
				for (s in all)
					if (s.scriptName == path) { luaTrace('addLuaScript: The script "' + path + '" is already running!'); return; }
			new FunkinLua(path);  
		});

		addCallback("removeLuaScript", function(luaFile:String) {
			var path:String = findScript(luaFile);
			var found:Bool = false;
			if (path != null)
				for (s in all.copy())
					if (s.scriptName == path) { s.stop(); found = true; }
			if (!found) luaTrace("removeLuaScript: Script " + luaFile + " isn't running!");
			return found;
		});

		addCallback("addHScript", function(scriptFile:String, ?ignoreAlreadyRunning:Bool = false) {
			var path:String = findScript(scriptFile, '.hx');
			if (path == null) { luaTrace("addHScript: Script doesn't exist!"); return; }
			try PlayState.instance.scripts.importScript(path) catch (e:Dynamic) luaTrace('addHScript: ' + Std.string(e));
		});

		addCallback("removeHScript", function(scriptFile:String) {
			var path:String = findScript(scriptFile, '.hx');
			var found:Bool = false;
			if (path != null) {
				try {
					for (s in PlayState.instance.scripts.scripts.copy())
						if (s.path == path) {
							s.destroy();
							PlayState.instance.scripts.remove(s);
							found = true;
						}
				} catch (e:Dynamic) {}
			}
			if (!found) luaTrace("removeHScript: Script " + scriptFile + " isn't running!");
			return found;
		});

		addCallback("setVar", function(varName:String, value:Dynamic) {
			getVariables().set(varName, value);
			return value;
		});
		addCallback("getVar", function(varName:String) {
			return getVariables().get(varName);
		});

		addCallback("close", function() {
			closed = true;
			trace('Closing script $scriptName');
			return true;
		});

		addCallback("getModSetting", function(saveTag:String, ?modName:String = null) {
			luaTrace("getModSetting: Codename Engine no tiene mod settings de Psych.");
			return null;
		});

		///////// SPRITES
		addCallback("loadGraphic", function(variable:String, image:String, ?gridX:Int = 0, ?gridY:Int = 0) {
			var spr:Dynamic = getProperty(variable);
			if (spr == null) spr = resolveObject(variable);
			if (spr != null && image != null && image.length > 0)
				spr.loadGraphic(Paths.image(image), gridX != 0 || gridY != 0, gridX, gridY);
		});

		addCallback("loadFrames", function(variable:String, image:String, ?spriteType:String = 'auto') {
			var spr:Dynamic = getProperty(variable);
			if (spr == null) spr = resolveObject(variable);
			if (spr != null && image != null && image.length > 0)
				LuaUtils.loadFrames(spr, image, spriteType);
		});

		addCallback("loadMultipleFrames", function(variable:String, images:Array<String>) {
			var spr:Dynamic = getProperty(variable);
			if (spr == null) spr = resolveObject(variable);
			if (spr == null || images == null || images.length < 1) return;
			LuaUtils.loadFrames(spr, images[0], 'auto');
			for (i in 1...images.length) {
				try spr.frames.addAtlas(Paths.getSparrowAtlas(images[i])) catch (e:Dynamic) luaTrace('loadMultipleFrames: no se pudo anadir ' + images[i]);
			}
		});

		addCallback("getObjectOrder", function(obj:String, ?group:String = null) {
			var leObj:Dynamic = resolveObject(obj);
			if (leObj == null) { luaTrace("getObjectOrder: Object " + obj + " doesn't exist!"); return -1; }
			var grp:Dynamic = group != null ? getProperty(group) : LuaUtils.getTargetInstance();
			if (grp == null) { luaTrace("getObjectOrder: Group " + group + " doesn't exist!"); return -1; }
			if (Std.isOfType(grp, Array)) return grp.indexOf(leObj);
			return Reflect.getProperty(grp, 'members').indexOf(leObj);
		});

		addCallback("addAnimation", function(obj:String, name:String, frames:Any, ?framerate:Float = 24, ?loop:Bool = true) {
			return LuaUtils.addAnimByIndices(obj, name, null, frames, framerate, loop);
		});

		addCallback("addOffset", function(obj:String, anim:String, x:Float, y:Float) {
			var o:Dynamic = getLuaObject(obj);
			if (o == null) o = resolveObject(obj);
			if (o != null && Std.isOfType(o, FunkinSprite)) {
				var fs:FunkinSprite = cast o;
				fs.addOffset(anim, x, y);
				return true;
			}
			return false;
		});

		///////// NOTE
		addCallback("noteTweenX", function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return noteTweenFunction(tag, note, {x: value}, duration, ease);
		});
		addCallback("noteTweenY", function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return noteTweenFunction(tag, note, {y: value}, duration, ease);
		});
		addCallback("noteTweenAngle", function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return noteTweenFunction(tag, note, {angle: value}, duration, ease);
		});
		addCallback("noteTweenAlpha", function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return noteTweenFunction(tag, note, {alpha: value}, duration, ease);
		});
		addCallback("noteTweenDirection", function(tag:String, note:Int, value:Float, duration:Float, ?ease:String = 'linear') {
			return noteTweenDirectionFunction(tag, note, value, duration, ease);
		});

		///////////PLAYSTATE
		addCallback("addHits", function(?value:Int = 0) {
			hits += value;
			setOnAll('hits', hits);
		});
		addCallback("setHits", function(?value:Int = 0) {
			hits = value;
			setOnAll('hits', hits);
		});

		addCallback("addCharacterToList", function(name:String, type:String) {
			trace('addCharacterToList: ' + name + ' ' + type + ' Codename already did this so...');
		});

		addCallback("triggerEvent", function(name:String, ?value1:Dynamic = '', ?value2:Dynamic = '') {
			try {
				PlayState.instance.executeEvent({name: name, time: Conductor.songPosition, params: [convertEventParam(value1), convertEventParam(value2)]});
				return true;
			} catch (e:Dynamic) {
				luaTrace('triggerEvent: ' + Std.string(e));
			}
			return false;
		});

		addCallback("startCountdown", function() {
			PlayState.instance.startCountdown();
			return true;
		});
		addCallback("endSong", function() {
			PlayState.instance.endSong();
			return true;
		});
		addCallback("restartSong", function(?skipTransition:Bool = false) {
			FlxG.resetState();
			return true;
		});
		addCallback("exitSong", function(?skipTransition:Bool = false) {
			var cls:Dynamic = Type.resolveClass(PlayState.isStoryMode ? 'funkin.menus.StoryMenuState' : 'funkin.menus.FreeplayState');
			if (cls == null) { luaTrace('exitSong: no encontre el menu de destino'); return false; }
			FlxG.switchState(Type.createInstance(cls, []));
			return true;
		});
		addCallback("loadSong", function(?name:String = null, ?difficulty:Dynamic = null) {
			if (name == null || name.length < 1) name = PlayState.SONG.meta.name;
			if (difficulty == null || Std.isOfType(difficulty, Float)) difficulty = PlayState.difficulty;
			PlayState.loadSong(name, difficulty);
			FlxG.switchState(new PlayState());
		});

		addCallback("getSongPosition", function() {
			return Conductor.songPosition;
		});

		addCallback("getCharacterX", function(type:String) {
			var c:Dynamic = getChar(type);
			return c != null ? c.x : 0;
		});
		addCallback("setCharacterX", function(type:String, value:Float) {
			var c:Dynamic = getChar(type);
			if (c != null) c.x = value;
		});
		addCallback("getCharacterY", function(type:String) {
			var c:Dynamic = getChar(type);
			return c != null ? c.y : 0;
		});
		addCallback("setCharacterY", function(type:String, value:Float) {
			var c:Dynamic = getChar(type);
			if (c != null) c.y = value;
		});

		addCallback("cameraSetTarget", function(target:String) {
			var g:PlayState = PlayState.instance;
			if (g == null) return;
			var sls:Array<Dynamic> = g.strumLines.members;
			var idx:Int = sls.length > 1 ? 1 : 0;      // bf
			switch (target.trim().toLowerCase()) {
				case 'dad' | 'opponent':
					idx = 0;
				case 'gf' | 'girlfriend':
					for (i in 0...sls.length)
						if (sls[i].characters != null && sls[i].characters.length > 0 && sls[i].characters[0] == g.gf) idx = i;
			}
			g.curCameraTarget = idx;
			g.moveCamera();
		});

		addCallback("setRatingPercent", function(value:Float) { setOnAll('rating', value); });
		addCallback("setRatingName", function(value:String) { setOnAll('ratingName', value); });
		addCallback("setRatingFC", function(value:String) { setOnAll('ratingFC', value); });
		addCallback("updateScoreText", function() {});   

		addCallback("startDialogue", function(dialogueFile:String, ?music:String = null) {
			luaTrace('startDialogue: Codename no usa los dialogos de Psych; continuando.');
			PlayState.instance.startCountdown();
			return false;
		});
		addCallback("startVideo", function(videoFile:String, ?canSkip:Bool = true, ?forMidSong:Bool = false, ?shouldLoop:Bool = false, ?playOnLoad:Bool = true) {
			var g:PlayState = PlayState.instance;
			var path:String = Paths.video(videoFile);
			if (g == null || !Assets.exists(path)) {
				luaTrace('startVideo: Couldnt find video file: ' + videoFile, false, false, FlxColor.RED);
				if (g != null && !forMidSong) g.startCountdown();
				return false;
			}
			if (!forMidSong) g.inCutscene = true;
			g.persistentUpdate = false;
			g.openSubState(new VideoCutscene(path, function() {
				if (!forMidSong) g.inCutscene = false;
				g.persistentUpdate = true;
				g.persistentDraw = true;
				if (!forMidSong) g.startCountdown();
			}));
			g.persistentDraw = false;
			return true;
		});

		///////// Sound 2
		addCallback("soundFadeOut", function(tag:String, duration:Float, ?toValue:Float = 0) {
			var snd:Dynamic = getSound(tag);
			if (snd != null) snd.fadeOut(duration, toValue);
		});
		addCallback("soundFadeCancel", function(tag:String) {
			var snd:Dynamic = getSound(tag);
			if (snd != null && snd.fadeTween != null) snd.fadeTween.cancel();
		});
		addCallback("getSoundVolume", function(tag:String) {
			var snd:Dynamic = getSound(tag);
			return snd != null ? snd.volume : 0;
		});
		addCallback("getSoundTime", function(tag:String) {
			var snd:Dynamic = getSound(tag);
			return snd != null ? snd.time : 0;
		});
		addCallback("setSoundTime", function(tag:String, value:Float) {
			var snd:Dynamic = getSound(tag);
			if (snd != null) snd.time = value;
		});
		addCallback("getSoundPitch", function(tag:String) {
			var snd:Dynamic = getSound(tag);
			return snd != null ? Reflect.getProperty(snd, 'pitch') : 1;
		});
		addCallback("setSoundPitch", function(tag:String, value:Float, ?doPause:Bool = false) {
			var snd:Dynamic = getSound(tag);
			if (snd == null) return;
			var wasPlaying:Bool = snd.playing;
			if (doPause) snd.pause();
			Reflect.setProperty(snd, 'pitch', value);
			if (doPause && wasPlaying) snd.play();
		});

		///////// TEXTS
		addCallback("makeLuaText", function(tag:String, ?text:String = '', ?width:Int = 0, ?x:Float = 0, ?y:Float = 0) {
			tag = tag.replace('.', '');
			LuaUtils.destroyObject(tag);
			var t:FlxText = new FlxText(x, y, width, text, 16);
			try {
				t.font = Paths.font('vcr.ttf');
			} catch (e:Dynamic) {}
			t.color = FlxColor.WHITE;
			t.alignment = 'center';
			setOutline(t, 2, FlxColor.BLACK);
			t.scrollFactor.set();
			getVariables().set(tag, t);
		});

		addCallback("setTextString", function(tag:String, text:String) {
			var t:FlxText = getText(tag);
			if (t != null) { t.text = text; return true; }
			luaTrace("setTextString: Object " + tag + " doesn't exist!");
			return false;
		});
		addCallback("setTextSize", function(tag:String, size:Int) {
			var t:FlxText = getText(tag);
			if (t != null) { t.size = size; return true; }
			return false;
		});
		addCallback("setTextWidth", function(tag:String, width:Float) {
			var t:FlxText = getText(tag);
			if (t != null) { t.fieldWidth = width; return true; }
			return false;
		});
		addCallback("setTextHeight", function(tag:String, height:Float) {
			var t:FlxText = getText(tag);
			if (t != null) { t.fieldHeight = height; return true; }
			return false;
		});
		addCallback("setTextAutoSize", function(tag:String, value:Bool) {
			var t:FlxText = getText(tag);
			if (t != null) { t.autoSize = value; return true; }
			return false;
		});
		addCallback("setTextBorder", function(tag:String, size:Float, color:String) {
			var t:FlxText = getText(tag);
			if (t == null) return false;
			if (size > 0) setOutline(t, size, CoolUtil2.colorFromString(color));
			else { var bs:Dynamic = borderStyleOf('NONE'); if (bs != null) t.borderStyle = bs; }
			return true;
		});
		addCallback("setTextColor", function(tag:String, color:String) {
			var t:FlxText = getText(tag);
			if (t != null) { t.color = CoolUtil2.colorFromString(color); return true; }
			return false;
		});
		addCallback("setTextFont", function(tag:String, newFont:String) {
			var t:FlxText = getText(tag);
			if (t != null) { t.font = Paths.font(newFont); return true; }
			return false;
		});
		addCallback("setTextItalic", function(tag:String, italic:Bool) {
			var t:FlxText = getText(tag);
			if (t != null) { t.italic = italic; return true; }
			return false;
		});
		addCallback("setTextAlignment", function(tag:String, ?alignment:String = 'left') {
			var t:FlxText = getText(tag);
			if (t == null) return false;
			if (alignment == null) alignment = 'left';
			switch (alignment.trim().toLowerCase()) {
				case 'right':
					t.alignment = 'right';
				case 'center':
					t.alignment = 'center';
				default:
					t.alignment = 'left';
			}
			return true;
		});
		addCallback("getTextString", function(tag:String) {
			var t:FlxText = getText(tag);
			return t != null ? t.text : null;
		});
		addCallback("getTextSize", function(tag:String) {
			var t:FlxText = getText(tag);
			return t != null ? t.size : -1;
		});
		addCallback("getTextFont", function(tag:String) {
			var t:FlxText = getText(tag);
			return t != null ? t.font : null;
		});
		addCallback("getTextWidth", function(tag:String) {
			var t:FlxText = getText(tag);
			return t != null ? t.fieldWidth : 0;
		});
		addCallback("addLuaText", function(tag:String, ?inFront:Bool = true) {
			var t:FlxText = getText(tag);
			if (t == null) return;
			var inst:Dynamic = LuaUtils.getTargetInstance();
			if (inst.members.indexOf(t) < 0) inst.add(t);
		});
		addCallback("removeLuaText", function(tag:String, ?destroy:Bool = true) {
			var t:FlxText = getText(tag);
			if (t == null) return;
			LuaUtils.getTargetInstance().remove(t, true);
			if (destroy) { getVariables().remove(tag); t.destroy(); }
		});

		///////// CONTROLS
		addCallback("keyboardJustPressed", function(name:String) { return keyState('justPressed', name); });
		addCallback("keyboardPressed", function(name:String) { return keyState('pressed', name); });
		addCallback("keyboardReleased", function(name:String) { return keyState('justReleased', name); });

		addCallback("keyJustPressed", function(name:String) { return controlState(name, '_P'); });
		addCallback("keyPressed", function(name:String) { return controlState(name, ''); });
		addCallback("keyReleased", function(name:String) { return controlState(name, '_R'); });


		///////// RANDOM
		addCallback("getRandomInt", function(?min:Int = 0, ?max:Int = 2147483647, ?exclude:String = '') {
			if (min == null) min = 0;
			if (max == null) max = 2147483647;
			if (exclude == null) exclude = '';
			var ex:Array<Int> = [];
			for (s in exclude.split(',')) {
				var n:Null<Int> = Std.parseInt(s.trim());
				if (n != null) ex.push(n);
			}
			return FlxG.random.int(min, max, ex);
		});
		addCallback("getRandomFloat", function(?min:Float = 0, ?max:Float = 1, ?exclude:String = '') {
			if (min == null) min = 0;
			if (max == null) max = 1;
			if (exclude == null) exclude = '';
			var ex:Array<Float> = [];
			for (s in exclude.split(',')) {
				var n:Float = Std.parseFloat(s.trim());
				if (!Math.isNaN(n)) ex.push(n);
			}
			return FlxG.random.float(min, max, ex);
		});
		addCallback("getRandomBool", function(?chance:Float = 50) {
			if (chance == null) chance = 50;
			return FlxG.random.bool(chance);
		});

		addCallback("stringStartsWith", function(str:String, start:String) { return str.startsWith(start); });
		addCallback("stringEndsWith", function(str:String, end:String) { return str.endsWith(end); });
		addCallback("stringSplit", function(str:String, split:String) { return str.split(split); });
		addCallback("stringTrim", function(str:String) { return str.trim(); });

		///////// FILES
		addCallback("checkFileExists", function(filename:String, ?absolute:Bool = false) {
			if (absolute) return FileSystem.exists(filename);
			return Assets.exists(Paths.getPath(filename)) || FileSystem.exists(filename);
		});
		addCallback("getTextFromFile", function(path:String, ?ignoreModFolders:Bool = false) {
			var p:String = Paths.getPath(path);
			if (Assets.exists(p)) return Assets.getText(p);
			if (FileSystem.exists(path)) return File.getContent(path);
			return null;
		});
		addCallback("saveFile", function(path:String, content:String, ?absolute:Bool = false) {
			try {
				var full:String = absolute ? path : (modFolder != null ? 'mods/' + modFolder + '/' + path : path);
				var dir:String = full.substr(0, full.lastIndexOf('/'));
				if (dir.length > 0 && !FileSystem.exists(dir)) FileSystem.createDirectory(dir);
				File.saveContent(full, content);
				return true;
			} catch (e:Dynamic) luaTrace('saveFile: ' + Std.string(e));
			return false;
		});
		addCallback("deleteFile", function(path:String, ?ignoreModFolders:Bool = false) {
			try {
				var full:String = (modFolder != null && !ignoreModFolders) ? 'mods/' + modFolder + '/' + path : path;
				if (FileSystem.exists(full)) { FileSystem.deleteFile(full); return true; }
			} catch (e:Dynamic) luaTrace('deleteFile: ' + Std.string(e));
			return false;
		});
		addCallback("directoryFileList", function(folder:String) {
			var list:Array<String> = [];
			try {
				for (f in Paths.getFolderContent(folder, false)) if (!list.contains(f)) list.push(f);
			} catch (e:Dynamic) {}
			return list;
		});

		///////// HSCRIPT
		addCallback("runHaxeCode", function(codeToRun:String, ?varsToBring:Dynamic = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
			return runHaxeCode(codeToRun, varsToBring, funcToRun, funcArgs);
		});

		addCallback("runHaxeFunction", function(funcToRun:String, ?funcArgs:Array<Dynamic> = null):Dynamic {
			if (hscript == null) {
				luaTrace('runHaxeFunction: HScript has not been initialized yet! Use "runHaxeCode" to initialize it');
				return null;
			}
			return hscriptCall(funcToRun, funcArgs);
		});

		addCallback("addHaxeLibrary", function(libName:String, ?libPackage:String = '') {
			if (libName == null) libName = '';
			var str:String = (libPackage != null && libPackage.length > 0) ? libPackage + '.' : '';
			var c:Dynamic = Type.resolveClass(str + libName);
			if (c == null) c = Type.resolveEnum(str + libName);
			if (c == null && str.length == 0) c = resolveClassByName(libName);
			if (c == null) {
				luaTrace('addHaxeLibrary: no se encontro ' + str + libName);
				return;
			}
			hscriptLibs.set(libName, c);
			if (hscript != null) {
				try {
					hscript.set(libName, c);
				} catch (e:Dynamic) {}
			}
		});

		addCallback("removeVar", function(name:String) {
			var variables = getVariables();
			if (variables.exists(name)) {
				variables.remove(name);
				return true;
			}
			return false;
		});

		///////// GAMEPADS
		addCallback("anyGamepadJustPressed", function(name:String) { return FlxG.gamepads.anyJustPressed(gpId(name)); });
		addCallback("anyGamepadPressed", function(name:String) { return FlxG.gamepads.anyPressed(gpId(name)); });
		addCallback("anyGamepadReleased", function(name:String) { return FlxG.gamepads.anyJustReleased(gpId(name)); });

		addCallback("gamepadAnalogX", function(id:Int, ?leftStick:Bool = true) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return 0.0;
			return controller.getXAxis(leftStick ? FlxGamepadInputID.LEFT_ANALOG_STICK : FlxGamepadInputID.RIGHT_ANALOG_STICK);
		});
		addCallback("gamepadAnalogY", function(id:Int, ?leftStick:Bool = true) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return 0.0;
			return controller.getYAxis(leftStick ? FlxGamepadInputID.LEFT_ANALOG_STICK : FlxGamepadInputID.RIGHT_ANALOG_STICK);
		});
		addCallback("gamepadJustPressed", function(id:Int, name:String) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;
			return Reflect.getProperty(controller.justPressed, name) == true;
		});
		addCallback("gamepadPressed", function(id:Int, name:String) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;
			return Reflect.getProperty(controller.pressed, name) == true;
		});
		addCallback("gamepadReleased", function(id:Int, name:String) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;
			return Reflect.getProperty(controller.justReleased, name) == true;
		});

		///////// SHADERS
		addCallback("initLuaShader", function(name:String, ?glslVersion:Dynamic = null) {
			if (!opt(['gameplayShaders', 'shaders'], true)) {
				luaTrace('initLuaShader: los shaders estan desactivados en las opciones');
				return false;
			}
			return initLuaShader(name);
		});

		addCallback("setSpriteShader", function(obj:String, shader:String) {
			if (!opt(['gameplayShaders', 'shaders'], true)) { luaTrace('setSpriteShader: los shaders estan desactivados en las opciones'); return false; }
			if (!shaderNames.exists(shader) && !initLuaShader(shader)) {
				luaTrace('setSpriteShader: Shader $shader is missing!');
				return false;
			}
			var spr:Dynamic = getShaderTarget(obj);
			if (spr == null) { luaTrace('setSpriteShader: Object $obj not found'); return false; }
			try {
				var sh:Dynamic = new CustomShader(shader);
				if (Std.isOfType(spr, FlxCamera)) {
					removeShaderFrom(obj, spr);
					spr.addShader(sh);             
				} else {
					spr.shader = sh;
				}
				objShaders.set(obj, sh);            
				return true;
			} catch (e:Dynamic) luaTrace('setSpriteShader: ' + Std.string(e));
			return false;
		});

		addCallback("removeSpriteShader", function(obj:String) {
			var spr:Dynamic = getShaderTarget(obj);
			if (spr == null) return false;
			removeShaderFrom(obj, spr);
			if (!Std.isOfType(spr, FlxCamera)) spr.shader = null;
			objShaders.remove(obj);
			return true;
		});

		addCallback("getShaderBool", function(obj:String, prop:String) {
			return shaderGet(obj, prop, 'getShaderBool');
		});
		addCallback("getShaderBoolArray", function(obj:String, prop:String) {
			return shaderGet(obj, prop, 'getShaderBoolArray');
		});
		addCallback("getShaderInt", function(obj:String, prop:String) {
			return shaderGet(obj, prop, 'getShaderInt');
		});
		addCallback("getShaderIntArray", function(obj:String, prop:String) {
			return shaderGet(obj, prop, 'getShaderIntArray');
		});
		addCallback("getShaderFloat", function(obj:String, prop:String) {
			return shaderGet(obj, prop, 'getShaderFloat');
		});
		addCallback("getShaderFloatArray", function(obj:String, prop:String) {
			return shaderGet(obj, prop, 'getShaderFloatArray');
		});

		addCallback("setShaderBool", function(obj:String, prop:String, value:Bool) {
			return shaderSet(obj, prop, value, 'setShaderBool');
		});
		addCallback("setShaderBoolArray", function(obj:String, prop:String, values:Dynamic) {
			return shaderSet(obj, prop, values, 'setShaderBoolArray');
		});
		addCallback("setShaderInt", function(obj:String, prop:String, value:Int) {
			return shaderSet(obj, prop, value, 'setShaderInt');
		});
		addCallback("setShaderIntArray", function(obj:String, prop:String, values:Dynamic) {
			var ints:Array<Dynamic> = [];
			if (values != null) for (v in (values : Array<Dynamic>)) ints.push(Std.int(v));
			return shaderSet(obj, prop, ints, 'setShaderIntArray');
		});
		addCallback("setShaderFloat", function(obj:String, prop:String, value:Float) {
			return shaderSet(obj, prop, value, 'setShaderFloat');
		});
		addCallback("setShaderFloatArray", function(obj:String, prop:String, values:Dynamic) {
			return shaderSet(obj, prop, values, 'setShaderFloatArray');
		});
		addCallback("setShaderSampler2D", function(obj:String, prop:String, bitmapdataPath:String) {
			var s:Dynamic = getShader(obj, 'setShaderSampler2D');
			if (s == null) return false;
			try {
				var graphic:Dynamic = FlxG.bitmap.add(Paths.image(bitmapdataPath));
				if (graphic != null) {
					s.hset(prop, graphic);
					return true;
				}
			} catch (e:Dynamic) {
				luaTrace('setShaderSampler2D: ' + Std.string(e));
			}
			return false;
		});

		load();
	}

	var hscript:Dynamic = null;
	var hscriptLibs:StringMap<Dynamic> = new StringMap<Dynamic>();
	var shaderNames:StringMap<Bool> = new StringMap<Bool>();

	function initLuaShader(name:String):Bool {
		if (shaderNames.exists(name)) return true;
		if (!Assets.exists(Paths.fragShader(name)) && !Assets.exists(Paths.vertShader(name))) {
			luaTrace('initLuaShader: Shader ' + name + ' is missing!');
			return false;
		}
		shaderNames.set(name, true);
		return true;
	}

	function getShaderTarget(obj:String):Dynamic {
		var o:Dynamic = getLuaObject(obj);
		if (o != null) return o;
		var split:Array<String> = obj.split('.');
		var target:Dynamic = resolveObject(split[0]);
		if (split.length > 1) target = getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
		return target;
	}

	function getShader(obj:String, ?fn:String = 'getShader'):Dynamic {
		var sh:Dynamic = objShaders.get(obj);        
		if (sh == null) {
			var target:Dynamic = getShaderTarget(obj);
			if (target == null) { luaTrace('$fn: Object $obj not found'); return null; }
			try sh = Reflect.getProperty(target, 'shader') catch (e:Dynamic) {}
		}
		if (sh == null) {
			luaTrace('$fn: Object $obj has no shader');
			return null;
		}
		return sh;
	}

	var objShaders:StringMap<Dynamic> = new StringMap<Dynamic>();

	function removeShaderFrom(obj:String, target:Dynamic):Void {
		var old:Dynamic = objShaders.get(obj);
		if (old != null && Std.isOfType(target, FlxCamera)) try target.removeShader(old) catch (e:Dynamic) {}
	}

	function gpId(name:String):FlxGamepadInputID {
		return FlxGamepadInputID.fromString(name == null ? '' : name.toUpperCase());
	}

	function isLuaSupported(v:Dynamic):Bool {
		return v == null || Std.isOfType(v, Bool) || Std.isOfType(v, Int) || Std.isOfType(v, Float)
			|| Std.isOfType(v, String) || Std.isOfType(v, Array)
			|| (Reflect.isObject(v) && Type.getClass(v) == null && Type.getEnum(v) == null);
	}

	function presetHScript(s:Dynamic, ?varsToBring:Dynamic = null):Void {
		var self:FunkinLua = this;
		s.set('parentLua', self);
		s.set('game', PlayState.instance);
		s.set('buildTarget', Lj.osName());

		s.set('Function_Stop', Function_Stop);
		s.set('Function_Continue', Function_Continue);
		s.set('Function_StopLua', Function_StopLua);
		s.set('Function_StopHScript', Function_StopHScript);
		s.set('Function_StopAll', Function_StopAll);

		s.set('setVar', function(name:String, value:Dynamic) { getVariables().set(name, value); return value; });
		s.set('getVar', function(name:String) { return getVariables().exists(name) ? getVariables().get(name) : null; });
		s.set('removeVar', function(name:String) {
			if (getVariables().exists(name)) { getVariables().remove(name); return true; }
			return false;
		});
		s.set('debugPrint', function(text:String, ?color:Int = null) {
			if (color == null) color = FlxColor.WHITE;
			try PlayState.instance.scripts.call('addTextToDebug', [text, color]) catch (e:Dynamic) trace(text);
		});

		s.set('createGlobalCallback', function(name:String, func:Dynamic) {
			for (lua in all)
				if (lua != null && !lua.closed && lua.L != null) lua.addCallback(name, func);
			customFunctions.set(name, func);
		});
		s.set('createCallback', function(name:String, func:Dynamic, ?funk:FunkinLua = null) {
			if (funk == null) funk = self;
			if (funk != null) funk.addCallback(name, func);
			else luaTrace('createCallback ($name): 3rd argument is null');
		});

		s.set('addHaxeLibrary', function(libName:String, ?libPackage:String = '') {
			var str:String = (libPackage != null && libPackage.length > 0) ? libPackage + '.' : '';
			var c:Dynamic = Type.resolveClass(str + libName);
			if (c == null) c = Type.resolveEnum(str + libName);
			if (c != null) s.set(libName, c);
		});

		for (name in hscriptLibs.keys()) s.set(name, hscriptLibs.get(name));

		if (varsToBring != null)
			for (key in Reflect.fields(varsToBring))
				s.set(StringTools.trim(key), Reflect.field(varsToBring, key));
	}

	function runHaxeCode(code:String, ?varsToBring:Dynamic = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
		if (code == null) return null;
		if (hscript != null) { try hscript.destroy() catch (e:Dynamic) {} hscript = null; }
		try {
			var s:Dynamic = Script.fromString(code, scriptName + '.hx');
			presetHScript(s, varsToBring);
			s.load();
			hscript = s;
		} catch (e:Dynamic) {
			luaTrace('runHaxeCode: ' + Std.string(e));
			hscript = null;
			return null;
		}
		if (funcToRun != null && funcToRun.length > 0) return hscriptCall(funcToRun, funcArgs);
		return null;
	}

	function hscriptCall(func:String, ?args:Array<Dynamic> = null):Dynamic {
		if (hscript == null || func == null) return null;
		try {
			var ret:Dynamic = hscript.call(func, args == null ? [] : args);
			return isLuaSupported(ret) ? ret : null;
		} catch (e:Dynamic) {
			luaTrace('runHaxeFunction ($func): ' + Std.string(e));
		}
		return null;
	}

	function load():Void {
		var prev = current; current = this;
		var realPath:String = scriptName;
		try {
			var p:String = Assets.getPath(scriptName); 
			if (p != null) realPath = p;
		} catch (e:Dynamic) {}

		var status:Int = Std.int(Lj.dofile(L, realPath));
		var err:String = null;
		if (status != 0) err = Lj.tostring(L, -1);
		Lj.settop(L, 0);
		current = prev;

		if (status != 0) {
			Logs.error('[Lua] Error loading $scriptName: $err');
			stop();
			return;
		}
		call('onCreate', []);
	}

	public function call(func:String, ?args:Array<Dynamic>):Dynamic {
		if (closed || L == null) return null;
		if (args == null) args = [];
		var prev = current; current = this;
		var ret:Dynamic = null;
		var top:Int = Lj.gettop(L);
		try {
			Lj.getglobal(L, func);
			if (Lj.isfunction(L, -1)) {
				for (a in args) Lj.pushValue(L, a);
				var status:Int = Std.int(Lj.pcall(L, args.length, 1, 0));
				if (status != 0) Logs.error('[Lua] Error in $func ($scriptName): ${Lj.tostring(L, -1)}');
				else ret = Lj.readValue(L, -1);
			}
		} catch (e:Dynamic) {
			Logs.error('[Lua] Error calling $func in $scriptName: ${Std.string(e)}');
		}
		if (L != null) Lj.settop(L, top);  
		current = prev;
		return ret;
	}

	public function set(variable:String, value:Dynamic):Void {
		if (closed || L == null) return;
		Lj.setGlobal(L, variable, value);
	}

	public function stop():Void {
		if (closed && L == null) return;
		closed = true;
		all.remove(this);
		callbacks.clear();
		if (hscript != null) { try hscript.destroy() catch (e:Dynamic) {} hscript = null; }
		if (L != null) { var s = L; L = null; Lj.close(s); }
	}

	function getLuaObject(tag:String):Dynamic return resolveObject(tag);

	function resolveObject(name:String):Dynamic {
		if (name == null) return null;
		var o:Dynamic = lookupObject(name);
		if (o != null) return o;
		var game:Dynamic = PlayState.instance;
		if (game != null) {
			var key:String = propAliases.exists(name) ? propAliases.get(name) : name;
			try {
				var p:Dynamic = Reflect.getProperty(game, key);
				if (p != null && Std.isOfType(p, FlxBasic)) return p;
			} catch (e:Dynamic) {}
			if (name.indexOf('.') >= 0 || name.indexOf('[') >= 0) {
				try {
					var q:Dynamic = getProperty(name);
					if (q != null && !Std.isOfType(q, String) && !Std.isOfType(q, Float) && !Std.isOfType(q, Bool)) return q;
				} catch (e:Dynamic) {}
			}
		}
		try { o = LuaUtils.getObjectDirectly(name); } catch (e:Dynamic) {}
		return o;
	}

	function tweenPrepare(tag:String, vars:String):Dynamic {
		if (tag != null) {
			var k:String = LuaUtils.formatVariable('tween_' + tag);
			var old:Dynamic = getVariables().get(k);
			if (old != null) { try old.cancel() catch (e:Dynamic) {} getVariables().remove(k); }
		}
		var t:Dynamic = resolveObject(vars);
		if (t != null) return t;
		try { return LuaUtils.tweenPrepare(null, vars); } catch (e:Dynamic) {}
		return null;
	}

	function borderStyleOf(name:String):Dynamic {
		try {
			var e:Dynamic = Type.resolveEnum('flixel.text.FlxTextBorderStyle');
			if (e != null) return Type.createEnum(e, name);
		} catch (e:Dynamic) {}
		return null;
	}

	function lookupObject(name:String):Dynamic {
		if (name == null) return null;
		var o:Dynamic = getVariables().get(name);
		if (o != null) return o;
		var game:Dynamic = PlayState.instance;
		if (game == null) return null;
		try {
			if (game.stage != null) {
				o = game.stage.getSprite(name);
				if (o != null) return o;
			}
		} catch (e:Dynamic) {}
		try {
			var pub:Dynamic = game.scripts.publicVariables;
			if (pub != null && pub.exists(name)) return pub.get(name);
		} catch (e:Dynamic) {}
		return null;
	}

	function isMap(o:Dynamic):Bool return o != null && Reflect.isFunction(Reflect.field(o, 'exists')) && Reflect.isFunction(Reflect.field(o, 'keys'));

	function getVarInArray(instance:Dynamic, variable:String, ?allowMaps:Bool = false):Dynamic {
		if (instance == null) return null;
		var parts:Array<String> = variable.split('[');
		var blah:Dynamic = (allowMaps && isMap(instance)) ? instance.get(parts[0]) : Reflect.getProperty(instance, parts[0]);
		for (i in 1...parts.length) {
			if (blah == null) return null;
			var key:Dynamic = parts[i].substr(0, parts[i].length - 1);
			var n:Null<Int> = Std.parseInt(key);
			if (n != null) key = n;
			blah = isMap(blah) ? blah.get(key) : blah[key];
		}
		return blah;
	}

	function setVarInArray(instance:Dynamic, variable:String, value:Dynamic, ?allowMaps:Bool = false):Dynamic {
		if (instance == null) return null;
		var parts:Array<String> = variable.split('[');
		if (parts.length == 1) {
			if (allowMaps && isMap(instance)) instance.set(variable, value);
			else Reflect.setProperty(instance, variable, value);
			return value;
		}
		var blah:Dynamic = (allowMaps && isMap(instance)) ? instance.get(parts[0]) : Reflect.getProperty(instance, parts[0]);
		for (i in 1...parts.length) {
			if (blah == null) return null;
			var key:Dynamic = parts[i].substr(0, parts[i].length - 1);
			var n:Null<Int> = Std.parseInt(key);
			if (n != null) key = n;
			if (i == parts.length - 1) {
				if (isMap(blah)) blah.set(key, value); else blah[key] = value;
				return value;
			}
			blah = isMap(blah) ? blah.get(key) : blah[key];
		}
		return value;
	}

	function getPath(root:Dynamic, path:String, ?allowMaps:Bool = false):Dynamic {
		var obj:Dynamic = root;
		for (part in path.split('.')) {
			if (obj == null) return null;
			obj = getVarInArray(obj, part, allowMaps);
		}
		return obj;
	}

	function setPath(root:Dynamic, path:String, value:Dynamic, ?allowMaps:Bool = false):Void {
		var split:Array<String> = path.split('.');
		var obj:Dynamic = root;
		for (i in 0...split.length - 1) {
			if (obj == null) return;
			obj = getVarInArray(obj, split[i], allowMaps);
		}
		setVarInArray(obj, split[split.length - 1], value, allowMaps);
	}

	function resolveRoot(variable:String):Array<Dynamic> {
		var firstDot:Int = variable.indexOf('.');
		var head:String = firstDot < 0 ? variable : variable.substr(0, firstDot);
		if (propAliases.exists(head)) variable = propAliases.get(head) + (firstDot < 0 ? '' : variable.substr(firstDot));
		var split:Array<String> = variable.split('.');
		if (split.length > 1 && split[0].indexOf('[') < 0) {
			var tagged:Dynamic = lookupObject(split[0]);
			if (tagged != null) return [tagged, split.slice(1).join('.')];
		}
		if (variable.indexOf('.') < 0 && variable.indexOf('[') < 0) {
			var single:Dynamic = lookupObject(variable);
			if (single != null) return [{ _o: single }, '_o'];
		}
		return [LuaUtils.getTargetInstance(), variable];
	}

	function getProperty(variable:String, ?allowMaps:Bool = false):Dynamic {
		if (variable == null) return null;
		var r:Array<Dynamic> = resolveRoot(variable);
		return getPath(r[0], r[1], allowMaps);
	}

	function setProperty(variable:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false):Void {
		if (variable == null) return;
		var r:Array<Dynamic> = resolveRoot(variable);
		setPath(r[0], r[1], parseInstance(value, allowInstances), allowMaps);
	}

	function parseInstance(value:Dynamic, allowInstances:Bool):Dynamic {
		if (allowInstances && Std.isOfType(value, String)) {
			var str:String = value;
			if (str.charAt(0) == '@') {
				var o:Dynamic = getVariables().get(str.substr(1));
				if (o != null) return o;
			}
		}
		return value;
	}

	function strumsOf(name:String):Array<Dynamic> {
		var g:Dynamic = PlayState.instance;
		if (g == null) return null;
		var out:Array<Dynamic> = [];
		try {
			switch (name) {
				case 'strumLineNotes':
					for (sl in g.strumLines.members) if (sl != null) for (st in sl.members) out.push(st);
				case 'playerStrums':
					for (st in g.playerStrums.members) out.push(st);
				case 'opponentStrums' | 'cpuStrums':
					for (st in g.cpuStrums.members) out.push(st);
				default:
					return null;
			}
		} catch (e:Dynamic) { return null; }
		return out;
	}

	function groupMember(group:String, index:Int):Dynamic {
		var sg:Array<Dynamic> = strumsOf(group);
		if (sg != null) return index >= 0 && index < sg.length ? sg[index] : null;
		var grp:Dynamic = getVariables().get(group);
		if (grp == null) grp = getProperty(group);
		if (grp == null) return null;
		if (Std.isOfType(grp, Array)) return grp[index];
		var members:Dynamic = Reflect.getProperty(grp, 'members');
		return members != null ? members[index] : null;
	}

	static var hits:Int = 0;

	public static function setOnAll(variable:String, value:Dynamic, ?exclusions:Array<String> = null):Void {
		for (s in all.copy())
			if (!s.closed && (exclusions == null || !exclusions.contains(s.scriptName))) s.set(variable, value);
	}

	public static function callOnAll(func:String, ?args:Array<Dynamic> = null, ?ignoreStops:Bool = false, ?exclusions:Array<String> = null, ?excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = Function_Continue;
		if (args == null) args = [];
		if (exclusions == null) exclusions = [];
		if (excludeValues == null) excludeValues = [Function_Continue];
		for (s in all.copy()) {
			if (s.closed || exclusions.contains(s.scriptName)) continue;
			var v:Dynamic = s.call(func, args);
			if ((v == Function_StopLua || v == Function_StopAll) && !excludeValues.contains(v) && !ignoreStops) {
				returnVal = v;
				break;
			}
			if (v != null && !excludeValues.contains(v)) returnVal = v;
		}
		return returnVal;
	}

	function withSelf(list:Array<String>, ignoreSelf:Bool):Array<String> {
		var r:Array<String> = list == null ? [] : list;
		if (ignoreSelf && !r.contains(scriptName)) r.push(scriptName);
		return r;
	}

	function luaTrace(text:String, ?ignoreCheck:Bool = false, ?deprecated:Bool = false, ?color:FlxColor):Void {
		if (color == null) color = FlxColor.RED;
		var msg:String = '[Lua] ' + text;
		if (color == FlxColor.RED) Logs.error(msg);
		else if (color == FlxColor.YELLOW || color == FlxColor.ORANGE) Logs.warn(msg);
		else Logs.infos(msg);
		try {
			PlayState.instance.scripts.call('addTextToDebug', [text, color]);
		} catch (e:Dynamic) {}
	}

	function findScript(scriptFile:String, ?ext:String = '.lua'):String {
		if (!scriptFile.endsWith(ext)) scriptFile += ext;
		var candidates:Array<String> = [scriptFile, 'data/lua/' + scriptFile, 'data/lua/scripts/' + scriptFile, 'data/scripts/' + scriptFile];
		try {
			var id:String = PlayState.instance.curSongID;
			if (id != null && id.length > 0) candidates.push('songs/' + id + '/scripts/' + scriptFile);
		} catch (e:Dynamic) {}
		for (c in candidates) {
			var p:String = Paths.getPath(c);
			if (Assets.exists(p)) return p;
		}
		return null;
	}

	function getChar(type:String):Dynamic {
		var g:Dynamic = PlayState.instance;
		switch (type.toLowerCase()) {
			case 'dad' | 'opponent': return g.dad;
			case 'gf' | 'girlfriend': return g.gf;
			default: return g.boyfriend;
		}
	}

	function getStrum(note:Int):Dynamic {
		var flat:Array<Dynamic> = [];
		for (sl in PlayState.instance.strumLines.members)
			for (s in sl.members) flat.push(s);
		return flat.length == 0 ? null : flat[note % flat.length];
	}

	function noteTweenFunction(tag:String, note:Int, data:Dynamic, duration:Float, ease:String):Dynamic {
		if (PlayState.instance == null) return null;
		var strum:Dynamic = getStrum(note);
		if (strum == null) return null;

		if (tag != null) {
			var originalTag:String = tag;
			LuaUtils.cancelTween(originalTag);
			tag = LuaUtils.formatVariable('tween_$tag');
			var variables = getVariables();
			variables.set(tag, FlxTween.tween(strum, data, duration, {
				ease: LuaUtils.getTweenEaseByString(ease),
				onComplete: function(twn:FlxTween) {
					variables.remove(tag);
					callOnAll('onTweenCompleted', [originalTag]);
				}
			}));
			return tag;
		}
		FlxTween.tween(strum, data, duration, {ease: LuaUtils.getTweenEaseByString(ease)});
		return null;
	}

	function getSound(tag:String):Dynamic {
		if (tag == null || tag.length < 1) return FlxG.sound.music;
		return getVariables().get(LuaUtils.formatVariable('sound_$tag'));
	}

	function getText(tag:String):FlxText {
		var t:Dynamic = getVariables().get(tag);
		return (t != null && Std.isOfType(t, FlxText)) ? t : null;
	}

	function setOutline(t:FlxText, size:Float, color:Int):Void {
		var bs:Dynamic = borderStyleOf('OUTLINE');
		if (bs != null) t.borderStyle = bs;
		t.borderSize = size;
		t.borderColor = color;
	}

	function keyState(kind:String, name:String):Bool {
		try {
			var list:Dynamic = Reflect.getProperty(FlxG.keys, kind);
			return Reflect.getProperty(list, name.toUpperCase()) == true;
		} catch (e:Dynamic) {}
		return false;
	}

	function controlState(name:String, suffix:String):Bool {
		try {
			var c:Dynamic = PlayState.instance.controls;
			var n:String = name.trim().toLowerCase();
			var field:String = null;
			switch (n) {
				case 'left' | 'down' | 'up' | 'right':
					field = 'NOTE_' + n.toUpperCase() + suffix;
				case 'accept' | 'back' | 'pause' | 'reset':
					var base:String = n.toUpperCase();
					field = suffix == '_P' ? base : (suffix == '_R' ? base + '_R' : base + '_HOLD');
				case 'space':
					return keyState(suffix == '_P' ? 'justPressed' : (suffix == '_R' ? 'justReleased' : 'pressed'), 'SPACE');
			}
			return field != null && Reflect.getProperty(c, field) == true;
		} catch (e:Dynamic) {}
		return false;
	}

	function gl(name:String, f:Void->Dynamic):Void {
		try Lj.setGlobal(L, name, f()) catch (e:Dynamic) {}
	}

	function opt(names:Array<String>, def:Dynamic):Dynamic {
		for (n in names) {
			try {
				var v:Dynamic = Reflect.getProperty(Options, n);
				if (v != null) return v;
			} catch (e:Dynamic) {}
		}
		return def;
	}

	function setGlobals():Void {
		var game:Dynamic = PlayState.instance;
		gl('luaDebugMode', function() return false);
		gl('luaDeprecatedWarnings', function() return true);
		gl('modFolder', function() return modFolder);
		gl('currentModDirectory', function() return modFolder);
		gl('screenWidth', function() return FlxG.width);
		gl('screenHeight', function() return FlxG.height);
		gl('buildTarget', function() return Lj.osName());

		gl('curBpm', function() return Conductor.bpm);
		gl('bpm', function() return Conductor.bpm);
		gl('crochet', function() return Conductor.crochet);
		gl('stepCrochet', function() return Conductor.stepCrochet);
		gl('scrollSpeed', function() return PlayState.SONG.scrollSpeed);
		gl('songLength', function() return game.inst.length);
		gl('songName', function() return PlayState.SONG.meta.name);
		gl('songPath', function() return PlayState.SONG.meta.name.toLowerCase().replace(' ', '-'));
		gl('curStage', function() return game.curStage);
		gl('isStoryMode', function() return PlayState.isStoryMode);
		gl('difficultyName', function() return PlayState.difficulty);
		gl('difficultyPath', function() return PlayState.difficulty.toLowerCase());
		gl('hasVocals', function() return PlayState.SONG.meta.needsVoices != false);
		gl('startedCountdown', function() return false);

		gl('curSection', function() return 0);
		gl('curDecBeat', function() return 0);
		gl('curDecStep', function() return 0);
		gl('score', function() return game.songScore);
		gl('misses', function() return game.misses);
		gl('hits', function() return hits);
		gl('combo', function() return game.combo);
		gl('rating', function() return 0);
		gl('ratingName', function() return '?');
		gl('ratingFC', function() return '');
		gl('inGameOver', function() return false);
		gl('mustHitSection', function() return false);
		gl('altAnim', function() return false);
		gl('gfSection', function() return false);
		gl('healthGainMult', function() return 1);
		gl('healthLossMult', function() return 1);
		gl('playbackRate', function() return 1);
		gl('botPlay', function() return game.strumLines.members[1].cpu);
		gl('practice', function() return false);

		gl('downscroll', function() return opt(['downscroll'], false));
		gl('middlescroll', function() return opt(['middleScroll', 'middlescroll'], false));
		gl('framerate', function() return opt(['framerate'], 60));
		gl('ghostTapping', function() return opt(['ghostTapping'], false));
		gl('flashingLights', function() return opt(['flashingMenu', 'flashingLights'], true));
		gl('cameraZoomOnBeat', function() return opt(['camZoomOnBeat', 'camZooms'], true));
		gl('lowQuality', function() return opt(['lowMemoryMode', 'lowQuality'], false));
		gl('shadersEnabled', function() return opt(['gameplayShaders', 'shaders'], true));
		gl('noteOffset', function() return opt(['songOffset', 'noteOffset'], 0));
		gl('hideHud', function() return false);
		gl('healthBarAlpha', function() return 1);

		for (i in 0...4) {
			gl('defaultPlayerStrumX' + i, function() return 0);
			gl('defaultPlayerStrumY' + i, function() return 0);
			gl('defaultOpponentStrumX' + i, function() return 0);
			gl('defaultOpponentStrumY' + i, function() return 0);
		}
	}

	public static function setStrumGlobals():Void {
		var game:Dynamic = PlayState.instance;
		if (game == null) return;
		try {
			var sls:Array<Dynamic> = game.strumLines.members;
			for (si in 0...2) {
				if (si >= sls.length) break;
				var pre:String = si == 1 ? 'Player' : 'Opponent';
				var strums:Array<Dynamic> = sls[si].members;
				for (i in 0...strums.length) {
					setOnAll('default' + pre + 'StrumX' + i, strums[i].x);
					setOnAll('default' + pre + 'StrumY' + i, strums[i].y);
				}
			}
		} catch (e:Dynamic) {}
		try {
			if (game.boyfriend != null) { setOnAll('defaultBoyfriendX', game.boyfriend.x); setOnAll('defaultBoyfriendY', game.boyfriend.y); setOnAll('boyfriendName', game.boyfriend.curCharacter); }
			if (game.dad != null) { setOnAll('defaultOpponentX', game.dad.x); setOnAll('defaultOpponentY', game.dad.y); setOnAll('dadName', game.dad.curCharacter); }
			if (game.gf != null) { setOnAll('defaultGirlfriendX', game.gf.x); setOnAll('defaultGirlfriendY', game.gf.y); setOnAll('gfName', game.gf.curCharacter); }
		} catch (e:Dynamic) {}
	}

	function oldTweenFunction(tag:String, vars:String, tweenValue:Dynamic, duration:Float, ease:String, funcName:String):Dynamic {
		var target:Dynamic = tweenPrepare(tag, vars);
		var variables = getVariables();
		if (target != null) {
			if (tag != null) {
				var originalTag:String = tag;
				tag = LuaUtils.formatVariable('tween_$tag');
				variables.set(tag, FlxTween.tween(target, tweenValue, duration, {
					ease: LuaUtils.getTweenEaseByString(ease),
					onComplete: function(twn:FlxTween) {
						variables.remove(tag);
						onTweenCompleted(originalTag, vars);
					}
				}));
				return tag;
			}
			FlxTween.tween(target, tweenValue, duration, {ease: LuaUtils.getTweenEaseByString(ease)});
		}
		return null;
	}

	static var classAliases:Map<String, String> = [
		'PlayState' => 'funkin.game.PlayState',
		'Conductor' => 'funkin.backend.system.Conductor',
		'Paths' => 'funkin.backend.assets.Paths',
		'CoolUtil' => 'funkin.backend.utils.CoolUtil',
		'Character' => 'funkin.game.Character',
		'Note' => 'funkin.game.Note',
		'StrumNote' => 'funkin.game.Strum',
		'ClientPrefs' => 'funkin.options.Options',
		'Options' => 'funkin.options.Options',
		'MusicBeatState' => 'funkin.backend.MusicBeatState',
		'GameOverSubstate' => 'funkin.game.GameOverSubstate',
		'Main' => 'funkin.backend.system.Main',
		'FlxG' => 'flixel.FlxG',
		'FlxSprite' => 'flixel.FlxSprite',
		'FlxText' => 'flixel.text.FlxText',
		'FlxCamera' => 'flixel.FlxCamera',
		'FlxTween' => 'flixel.tweens.FlxTween',
		'FlxEase' => 'flixel.tweens.FlxEase',
		'FlxMath' => 'flixel.math.FlxMath',
		'FlxTimer' => 'flixel.util.FlxTimer',
		'FlxSound' => 'flixel.sound.FlxSound'
	];

	static var propAliases:Map<String, String> = [
		'opponentStrums' => 'cpuStrums',
		'boyfriendGroup' => 'boyfriend',
		'dadGroup' => 'dad',
		'gfGroup' => 'gf'
	];

	function resolveClassByName(name:String):Dynamic {
		if (name == null) return null;
		var c:Dynamic = Type.resolveClass(name);
		if (c == null && classAliases.exists(name)) c = Type.resolveClass(classAliases.get(name));
		return c;
	}

	function tweenTypeFromString(t:String):FlxTweenType {
		if (t == null) return 8;
		switch (t.toLowerCase().trim()) {
			case 'backward': return 16;
			case 'looping': return 2;
			case 'persist': return 1;
			case 'pingpong': return 4;
			default: return 8;
		}
	}

	function refreshRating():Void {
		try {
			PlayState.instance.updateRating();
		} catch (e:Dynamic) {}
	}

	function lowestCharacterIndex(instance:Dynamic):Int {
		var lowest:Int = -1;
		try {
			for (sl in PlayState.instance.strumLines.members) {
				if (sl == null || sl.characters == null) continue;
				for (c in sl.characters) {
					var i:Int = instance.members.indexOf(c);
					if (i >= 0 && (lowest < 0 || i < lowest)) lowest = i;
				}
			}
		} catch (e:Dynamic) {}
		return lowest;
	}

	function convertEventParam(v:Dynamic):Dynamic {
		if (v == null || !Std.isOfType(v, String)) return v;
		var s:String = Std.string(v).trim();
		if (s == 'true') return true;
		if (s == 'false') return false;
		var f:Float = Std.parseFloat(s);
		if (!Math.isNaN(f)) {
			var i:Null<Int> = Std.parseInt(s);
			if (i != null && Std.string(i) == s) return i;
			return f;
		}
		return v;
	}

	function shaderGet(obj:String, prop:String, fn:String):Dynamic {
		var s:Dynamic = getShader(obj, fn);
		if (s == null) return null;
		try {
			return s.hget(prop);
		} catch (e:Dynamic) {
			luaTrace(fn + ': ' + Std.string(e));
		}
		return null;
	}

	function shaderSet(obj:String, prop:String, value:Dynamic, fn:String):Bool {
		var s:Dynamic = getShader(obj, fn);
		if (s == null) return false;
		try {
			s.hset(prop, value);
			return true;
		} catch (e:Dynamic) {
			luaTrace(fn + ': ' + Std.string(e));
		}
		return false;
	}

	function noteTweenDirectionFunction(tag:String, note:Int, value:Float, duration:Float, ease:String):Dynamic {
		if (PlayState.instance == null) return null;
		var strum:Dynamic = getStrum(note);
		if (strum == null) return null;

		var current:Float = strum.noteAngle != null ? strum.noteAngle : strum.angle;
		var proxy:Dynamic = {d: current + 90};
		var apply:FlxTween->Void = function(twn:FlxTween) {
			strum.noteAngle = proxy.d - 90;
		};

		var variables = getVariables();
		var originalTag:String = tag;
		if (tag != null) {
			LuaUtils.cancelTween(originalTag);
			tag = LuaUtils.formatVariable('tween_$tag');
		}
		var tw:FlxTween = FlxTween.tween(proxy, {d: value}, duration, {
			ease: LuaUtils.getTweenEaseByString(ease),
			onUpdate: apply,
			onComplete: function(twn:FlxTween) {
				apply(twn);
				if (originalTag != null) {
					variables.remove(tag);
					callOnAll('onTweenCompleted', [originalTag]);
				}
			}
		});
		if (originalTag != null) {
			variables.set(tag, tw);
			return tag;
		}
		return null;
	}	function onTweenCompleted(tag:String, vars:String):Void { call('onTweenCompleted', [tag, vars]); }
	function onTimerCompleted(tag:String, loops:Int, loopsLeft:Int):Void { call('onTimerCompleted', [tag, loops, loopsLeft]); }
	function onSoundFinished(tag:String):Void { call('onSoundFinished', [tag]); }
}

//////////FINALLY THEY ADDED
class Lj {
	static var ready:Bool = false;

	static var f_newstate:Dynamic;
	static var f_close:Dynamic;
	static var f_openlibs:Dynamic;
	static var f_gettop:Dynamic;
	static var f_settop:Dynamic;
	static var f_pop:Dynamic;
	static var f_type:Dynamic;
	static var f_isfunction:Dynamic;
	static var f_tonumber:Dynamic;
	static var f_tostring:Dynamic;
	static var f_toboolean:Dynamic;
	static var f_objlen:Dynamic;
	static var f_next:Dynamic;
	static var f_pushnil:Dynamic;
	static var f_pushnumber:Dynamic;
	static var f_pushboolean:Dynamic;
	static var f_pushstring:Dynamic;
	static var f_createtable:Dynamic;
	static var f_rawseti:Dynamic;
	static var f_rawgeti:Dynamic;
	static var f_setfield:Dynamic;
	static var f_getglobal:Dynamic;
	static var f_setglobal:Dynamic;
	static var f_pcall:Dynamic;
	static var f_dofile:Dynamic;
	static var f_add_cb:Dynamic;
	static var f_set_cbs:Dynamic;
	static var f_trace_func:Dynamic;
	static var f_trace_lib:Dynamic;

	public static function osName():String {
		#if windows return 'windows';
		#elseif linux return 'linux';
		#elseif mac return 'mac';
		#elseif android return 'android';
		#elseif ios return 'ios';
		#else return 'unknown';
		#end
	}

	public static function init():Void {
		if (ready) return;
		ready = true;
		var f = function(name:String, args:Int):Dynamic return NdllUtil.getFunction("luajit", name, args);

		f_newstate     = f("lj_newstate", 0);
		f_close        = f("lj_close", 1);
		f_openlibs     = f("lj_openlibs", 1);
		f_gettop       = f("lj_gettop", 1);
		f_settop       = f("lj_settop", 2);
		f_pop          = f("lj_pop", 2);
		f_type         = f("lj_type", 2);
		f_isfunction   = f("lj_isfunction", 2);
		f_tonumber     = f("lj_tonumber", 2);
		f_tostring     = f("lj_tostring", 2);
		f_toboolean    = f("lj_toboolean", 2);
		f_objlen       = f("lj_objlen", 2);
		f_next         = f("lj_next", 2);
		f_pushnil      = f("lj_pushnil", 1);
		f_pushnumber   = f("lj_pushnumber", 2);
		f_pushboolean  = f("lj_pushboolean", 2);
		f_pushstring   = f("lj_pushstring", 2);
		f_createtable  = f("lj_createtable", 3);
		f_rawseti      = f("lj_rawseti", 3);
		f_rawgeti      = f("lj_rawgeti", 3);
		f_setfield     = f("lj_setfield", 3);
		f_getglobal    = f("lj_getglobal", 2);
		f_setglobal    = f("lj_setglobal", 2); 
		f_pcall        = f("lj_pcall", 4);
		f_dofile       = f("lj_dofile", 2);
		f_add_cb       = f("lj_add_callback_function", 2);
		f_set_cbs      = f("lj_set_callbacks_function", 1);
		f_trace_func   = f("lj_register_hxtrace_func", 1);
		f_trace_lib    = f("lj_register_hxtrace_lib", 1);
	}

	public static inline function newstate():Dynamic return f_newstate();
	public static inline function close(L:Dynamic):Void f_close(L);
	public static inline function openlibs(L:Dynamic):Void f_openlibs(L);

	public static inline function gettop(L:Dynamic):Int return Std.int(f_gettop(L));
	public static inline function settop(L:Dynamic, i:Int):Void f_settop(L, i);
	public static inline function pop(L:Dynamic, n:Int):Void f_pop(L, n);
	public static inline function type(L:Dynamic, i:Int):Int return Std.int(f_type(L, i));
	public static inline function isfunction(L:Dynamic, i:Int):Bool return f_isfunction(L, i) == true;
	public static inline function tonumber(L:Dynamic, i:Int):Float return f_tonumber(L, i);
	public static inline function tostring(L:Dynamic, i:Int):String return f_tostring(L, i);
	public static inline function toboolean(L:Dynamic, i:Int):Bool return f_toboolean(L, i) == true;
	public static inline function objlen(L:Dynamic, i:Int):Int return Std.int(f_objlen(L, i));
	public static inline function next(L:Dynamic, i:Int):Int return Std.int(f_next(L, i));

	public static inline function pushnil(L:Dynamic):Void f_pushnil(L);
	public static inline function pushnumber(L:Dynamic, n:Float):Void f_pushnumber(L, n);
	public static inline function pushboolean(L:Dynamic, b:Bool):Void f_pushboolean(L, b);
	public static inline function pushstring(L:Dynamic, s:String):Void f_pushstring(L, s);
	public static inline function createtable(L:Dynamic, narr:Int, nrec:Int):Void f_createtable(L, narr, nrec);
	public static inline function rawseti(L:Dynamic, t:Int, n:Int):Void f_rawseti(L, t, n);
	public static inline function rawgeti(L:Dynamic, t:Int, n:Int):Void f_rawgeti(L, t, n);
	public static inline function setfield(L:Dynamic, t:Int, k:String):Void f_setfield(L, t, k);
	public static inline function getglobal(L:Dynamic, name:String):Void f_getglobal(L, name);
	public static inline function pcall(L:Dynamic, nargs:Int, nresults:Int, errfunc:Int):Int return Std.int(f_pcall(L, nargs, nresults, errfunc));
	public static inline function dofile(L:Dynamic, path:String):Int return Std.int(f_dofile(L, path));

	public static inline function addCallbackFunction(L:Dynamic, name:String):Void f_add_cb(L, name);
	public static inline function setCallbacksFunction(fn:Dynamic):Void f_set_cbs(fn);
	public static inline function registerHxtraceFunc(fn:Dynamic):Void f_trace_func(fn);
	public static inline function registerHxtraceLib(L:Dynamic):Void f_trace_lib(L);

	public static function setGlobal(L:Dynamic, name:String, value:Dynamic):Void {
		pushValue(L, value);
		f_setglobal(L, name);       
	}

	public static function readValue(L:Dynamic, idx:Int, depth:Int = 0):Dynamic {
		switch (type(L, idx)) {
			case 1: return toboolean(L, idx);
			case 3: return tonumber(L, idx);
			case 4: return tostring(L, idx);
			case 5: return depth > 8 ? null : readTable(L, idx, depth);
			default: return null;      
		}
	}

	static function readTable(L:Dynamic, idx:Int, depth:Int):Dynamic {
		var abs:Int = idx < 0 ? gettop(L) + idx + 1 : idx;  
		var n:Int = objlen(L, abs);
		if (n > 0) {
			var arr:Array<Dynamic> = [];
			for (i in 1...n + 1) {
				rawgeti(L, abs, i);
				arr.push(readValue(L, -1, depth + 1));
				pop(L, 1);
			}
			return arr;
		}
		var obj:Dynamic = {};
		pushnil(L);
		while (next(L, abs) != 0) {
			var kt:Int = type(L, -2);
			var key:String = null;
			if (kt == 4) key = tostring(L, -2);
			else if (kt == 3) key = Std.string(tonumber(L, -2));  
			if (key != null) Reflect.setField(obj, key, readValue(L, -1, depth + 1));
			pop(L, 1);                                         
		}
		return obj;
	}

	public static function pushValue(L:Dynamic, v:Dynamic, depth:Int = 0):Void {
		if (v == null || depth > 8) { pushnil(L); return; }
		if (Std.isOfType(v, Bool)) { pushboolean(L, v); return; }
		if (Std.isOfType(v, Int) || Std.isOfType(v, Float)) { pushnumber(L, v); return; }
		if (Std.isOfType(v, String)) { pushstring(L, v); return; }
		if (Std.isOfType(v, Array)) {
			var a:Array<Dynamic> = v;
			createtable(L, a.length, 0);
			for (i in 0...a.length) {
				pushValue(L, a[i], depth + 1);
				rawseti(L, -2, i + 1);
			}
			return;
		}
		if (Reflect.isObject(v) && Type.getClass(v) == null && Type.getEnum(v) == null) {
			createtable(L, 0, 4);
			for (f in Reflect.fields(v)) {
				pushValue(L, Reflect.field(v, f), depth + 1);
				setfield(L, -2, f);
			}
			return;
		}
		pushstring(L, Std.string(v));
	}
}
