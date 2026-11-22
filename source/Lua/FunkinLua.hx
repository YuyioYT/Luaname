package lua; 	///////////////////////FOR SOME REASON I CANT DIVIDE THE CALLBACKS ///////CREDITS TO YUYIOYT

import funkin.game.PlayState;
import funkin.game.Character;

import funkin.game.cutscenes.VideoCutscene;

import funkin.backend.assets.Paths;
import funkin.backend.system.Conductor;
import funkin.backend.system.Logs;

import funkin.backend.FunkinSprite;

import funkin.backend.scripting.Script;
import funkin.backend.shaders.CustomShader;
import funkin.backend.shaders.FunkinShader;

import openfl.filters.ShaderFilter;

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

import lua.Lj;
import lua.helpers.LuaShared;
import lua.helpers.LuaProps;
import lua.helpers.LuaCombo;
import lua.helpers.LuaShaders;
import lua.helpers.LuaEffects;
import lua.helpers.LuaTweens;
import lua.helpers.LuaFiles;
import lua.helpers.LuaCharacters;
import lua.helpers.LuaHaxe;
import lua.helpers.LuaGlobals;
import lua.helpers.LuaInput;

import funkin.backend.assets.ModsFolder;
import hxvlc.flixel.FlxVideoSprite;

using StringTools;

class FunkinLua {

	public var scriptName:String = '';
	public var modFolder:String = null;
	public var closed:Bool = false;
	public static var allowDuplicate:Bool = false;

	public static var customFunctions:StringMap<Dynamic> = LuaShared.customFunctions;
	public static var all:Array<Dynamic> = LuaShared.all;
	public static var current:FunkinLua = null;

	public static var Function_Stop:String = "##PSYCHLUA_FUNCTIONSTOP";
	public static var Function_Continue:String = "##PSYCHLUA_FUNCTIONCONTINUE";
	public static var Function_StopLua:String = "##PSYCHLUA_FUNCTIONSTOPLUA";
	public static var Function_StopHScript:String = "##PSYCHLUA_FUNCTIONSTOPHSCRIPT";
	public static var Function_StopAll:String = "##PSYCHLUA_FUNCTIONSTOPALL";

	/////////this doesnt work for now
	public static var countdownBlocked:Bool = false;

	public static var videoSprite:Dynamic = null;
	public static var videoCanSkip:Bool = false;
	public static var videoName:String = null;
	public static var videoMidSong:Bool = true;

	public static var gamePaused:Bool = false;

	static function normScript(p:String):String {
		var x:String = p.replace('\\', '/').toLowerCase();

		while (x.startsWith('./')) x = x.substr(2);

		var parts:Array<String> = x.split('/');

		if (parts.length > 2 && parts[0] == 'mods') parts = parts.slice(2);
		else if (parts.length > 1 && parts[0] == 'assets') parts = parts.slice(1);

		return parts.join('/');
	}

	public static function sameScript(a:String, b:String):Bool {
		if (a == null || b == null) return false;
		return a == b || FunkinLua.normScript(a) == FunkinLua.normScript(b);
	}

	public static function cancelTimerSafe(tag:String):Void {
		if (tag == null) return;

		var key:String = LuaUtils.formatVariable('timer_' + tag);
		var t:Dynamic = getVariables().get(key);

		if (t == null) { try LuaUtils.cancelTimer(tag) catch (e:Dynamic) {} return; }
		getVariables().remove(key);

		try t.cancel() catch (e:Dynamic) {}
		try t.destroy() catch (e:Dynamic) {}
	}

	public static function startLuaTimer(tag:String, time:Float, loops:Int):String {
		FunkinLua.cancelTimerSafe(tag);
		var variables = getVariables();
		var originalTag:String = tag;
		var key:String = LuaUtils.formatVariable('timer_' + tag);
		var timer:FlxTimer = new FlxTimer();
		variables.set(key, timer);
		timer.start(time, function(tmr:FlxTimer) {
			if (variables.get(key) != tmr) return; 
			if (tmr.finished) variables.remove(key);
			LuaShared.callOnAll('onTimerCompleted', [originalTag, tmr.loops, tmr.loopsLeft]);
		}, loops);
		return key;
	}

	static var countdownBlockOwner:Dynamic = null;

	static function enforceCountdownBlock():Void {
		if (!countdownBlocked) return;
		var g:Dynamic = PlayState.instance;
		if (g == null) { countdownBlocked = false; countdownBlockOwner = null; return; }
		if (countdownBlockOwner == null) countdownBlockOwner = g;
		else if (countdownBlockOwner != g) { countdownBlocked = false; countdownBlockOwner = null; return; } // otra partida (reinicio)
		try {
			if (g.startTimer != null && g.startTimer.active) g.startTimer.cancel();
			g.startedCountdown = false;
			if (g.inst != null && g.inst.playing) g.inst.stop();
			if (g.vocals != null && g.vocals.playing) g.vocals.stop();
			var sls:Array<Dynamic> = g.strumLines.members;
			for (sl in sls) if (sl != null && sl.vocals != null && sl.vocals.playing) sl.vocals.stop();
		} catch (e:Dynamic) {}
	}

	static var _variables:StringMap<Dynamic> = LuaShared.variables;
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
		var self:FunkinLua = current;
		if (self == null || self.L != state) {
			self = null;
			for (s in all) if (s.L == state) { self = s; break; }
			if (self == null) self = current;
		}
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

	public static var nilArithmeticSafe:Bool = true;

	public function new(scriptName:String) {
		var funk:FunkinLua = this;  
		this.scriptName = scriptName.trim();

		var parts:Array<String> = this.scriptName.replace('\\', '/').split('/');
		var mi:Int = parts.indexOf('mods');
		if (mi >= 0 && parts.length > mi + 1) this.modFolder = parts[mi + 1];

		var norm:String = this.scriptName.replace('\\', '/').toLowerCase();
		for (o in all) {
			if (o != null && !o.closed && o.scriptName.replace('\\', '/').toLowerCase() == norm && !allowDuplicate) {
				Logs.warn('[Lua] Script duplicado ignorado: ' + this.scriptName);
				closed = true;
				return;
			}
		}

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
		LuaGlobals.loadNilSafePrelude(funk, nilArithmeticSafe);

		Lj.setGlobal(L, 'Function_Stop', Function_Stop);
		Lj.setGlobal(L, 'Function_Continue', Function_Continue);
		Lj.setGlobal(L, 'Function_StopLua', Function_StopLua);
		Lj.setGlobal(L, 'Function_StopHScript', Function_StopHScript);
		Lj.setGlobal(L, 'Function_StopAll', Function_StopAll);
		Lj.setGlobal(L, 'scriptName', this.scriptName);
		Lj.setGlobal(L, 'curStep', 0);
		Lj.setGlobal(L, 'curBeat', 0);
		
		var __cm:String = ModsFolder.currentModFolder;
		if (__cm == null || __cm == '') __cm = this.modFolder;
		if (__cm == null) __cm = '';

		Lj.setGlobal(L, 'currentModDirectory', __cm);
		Lj.setGlobal(L, 'modFolder', __cm);
		Lj.setGlobal(L, 'version', '1.0.4');	/////////Putting psych version
		LuaGlobals.setGlobals(funk);

		for (name in customFunctions.keys()) {
			var func:Dynamic = customFunctions.get(name);
			if (func != null) addCallback(name, func);
		}	/////////Get the custom functions

		addCallback("debugPrint", function(?text:Dynamic = '', ?color:String = 'WHITE') {
			if (color == null || color == '') color = 'WHITE';
			var str:String = Std.string(text); Logs.infos('[Lua] ' + str); PlayState.instance.scripts.call('addTextToDebug', [str, CoolUtil2.colorFromString(color)]);
		});

		addCallback("makeLuaSprite", function(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0) {
			tag = tag.replace('.', '');
			LuaUtils.destroyObject(tag);
			objShaders.remove(tag);
			var leSprite:ModchartSprite = new ModchartSprite(x, y);
			leSprite.active = true;
			getVariables().set(tag, leSprite);
			if (image != null && image.length > 0) {
				try {
					var path:String = Paths.image(image);	////////Try to see if the image exist
					if (Assets.exists(path)) leSprite.loadGraphic(path); else LuaShared.luaTrace('makeLuaSprite: image ' + image + ' not found', false, false, FlxColor.YELLOW);
				} catch (e:Dynamic) {
					LuaShared.luaTrace('makeLuaSprite: could not load ' + image + ': ' + Std.string(e), false, false, FlxColor.YELLOW);
				}
			}
		});


		addCallback("makeAnimatedLuaSprite", function(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0, ?spriteType:String = 'auto') {
			tag = tag.replace('.', '');
			LuaUtils.destroyObject(tag);
			objShaders.remove(tag);
			var leSprite:ModchartSprite = new ModchartSprite(x, y);
			getVariables().set(tag, leSprite);
			if (image != null && image.startsWith('@char:')) {
				////////Exclusive of char
				var ch:Dynamic = LuaProps.resolveObject(funk, image.substr(6));
				if (ch != null && ch.frames != null) {
					leSprite.frames = ch.frames;
					leSprite.frame = ch.frame;
					leSprite.antialiasing = ch.antialiasing;
				} else LuaShared.luaTrace('makeAnimatedLuaSprite: the char ' + image.substr(6) + ' has no frames', false, false, FlxColor.YELLOW);

			} else if (image != null && image.length > 0) {
				try {
					LuaUtils.loadFrames(leSprite, image, spriteType);	/////////Try to load frames
				} catch (e:Dynamic) {
					LuaShared.luaTrace('makeAnimatedLuaSprite: could not load ' + image + ': ' + Std.string(e), false, false, FlxColor.YELLOW);
				}
			}
		});

		addCallback("makeGraphic", function(obj:String, width:Int = 256, height:Int = 256, color:String = 'FFFFFF') {
			var spr:FlxSprite = LuaProps.resolveObject(funk, obj);
			if (spr != null) spr.makeGraphic(width, height, CoolUtil2.colorFromString(color));
		});

		addCallback("addAnimationByPrefix", function(obj:String, name:String, prefix:String, framerate:Float = 24, loop:Bool = true) {
			var obj:FlxSprite = cast LuaUtils.resolveObject(funk, obj);
			if (prefix == null) return false;
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

		addCallback("addAnimation", function(obj:String, name:String, frames:Any, ?framerate:Float = 24, ?loop:Bool = true) {
			return LuaUtils.addAnimByIndices(obj, name, null, frames, framerate, loop);
		});

		addCallback("addAnimationByIndices", function(obj:String, name:String, prefix:String, indices:Any, framerate:Float = 24, loop:Bool = false) {
			return LuaUtils.addAnimByIndices(obj, name, prefix, indices, framerate, loop);
		});

		addCallback("playAnim", function(obj:String, name:String, ?forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0) {
			var obj:Dynamic = LuaUtils.getObjectDirectly(obj);
			if(obj == null) {
				LuaShared.luaTrace('playAnim: Target not found! Are you sure that "$obj" exists?: ' + obj, false, false, FlxColor.RED);
				return false;
			}
			if(obj.playAnim != null){
				obj.playAnim(name, forced, reverse, startFrame);
				return true;
			}else{
				if(obj.anim != null) obj.anim.play(name, forced, reverse, startFrame); //FlxAnimate
				else obj.animation.play(name, forced, reverse, startFrame);
				return true;
			}
			return false;
		});

		addCallback("addOffset", function(obj:String, anim:String, x:Float, y:Float) {
			var obj:Dynamic = LuaUtils.getObjectDirectly(obj);
			if(obj != null && obj.addOffset != null)
			{
				obj.addOffset(anim, x, y);
				return true;
			}
			return false;
		});

		addCallback("setScrollFactor", function(obj:String, scrollX:Float, scrollY:Float) {
			if(LuaUtils.getLuaObject(obj) != null) {
				LuaUtils.getLuaObject(obj).scrollFactor.set(scrollX, scrollY);
				return;
			}

			var object:FlxObject = Reflect.getProperty(LuaUtils.getTargetInstance(), obj);
			if(object != null) {
				object.scrollFactor.set(scrollX, scrollY);
			}
		});

		addCallback("objectPlayAnimation", function(obj:String, name:String, ?forced:Bool = false, ?startFrame:Int = 0) {
			LuaShared.luaTrace("objectPlayAnimation is deprecated! Use playAnim instead", false, true);
			if(LuaUtils.getLuaObject(obj) != null) {
				LuaUtils.getLuaObject(obj).animation.play(name, forced, false, startFrame);
				return true;
			}

			var spr:FlxSprite = Reflect.getProperty(LuaUtils.getTargetInstance(), obj);
			if(spr != null) {
				spr.animation.play(name, forced, false, startFrame);
				return true;
			}
			return false;
		});

		addCallback("addLuaSprite", function(tag:String, ?inFront:Bool = false) {
			var mySprite:FlxSprite = getVariables().get(tag);
			if (mySprite == null) return;

			var instance:Dynamic = LuaUtils.getTargetInstance();
			if (inFront) instance.add(mySprite);
			else instance.insert(instance.members.indexOf(LuaUtils.getLowestCharacterGroup()), mySprite);
		});

		addCallback("setGraphicSize", function(obj:String, x:Float, y:Float = 0, updateHitbox:Bool = true) {
			if(LuaUtils.getLuaObject(obj)!=null) {
				var shit:FlxSprite = LuaUtils.getLuaObject(obj);
				shit.setGraphicSize(x, y);
				if(updateHitbox) shit.updateHitbox();
				return;
			}

			var split:Array<String> = obj.split('.');
			var poop:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				poop = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(poop != null) {
				poop.setGraphicSize(x, y);
				if(updateHitbox) poop.updateHitbox();
				return;
			}
			LuaShared.luaTrace('setGraphicSize: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});

		addCallback("scaleObject", function(obj:String, x:Float, y:Float, updateHitbox:Bool = true) {
			if (LuaUtils.getLuaObject(obj) != null) {
				var shit:FlxSprite = LuaUtils.getLuaObject(obj);
				shit.scale.set(x, y);
				if (updateHitbox) shit.updateHitbox();
				return;
			}

			var split:Array<String> = obj.split('.');
			var poop:FlxSprite = LuaUtils.resolveObject(split[0]);
			if (split.length > 1) {
				poop = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
			}

			if (poop != null) {
				poop.scale.set(x, y);
				if (updateHitbox) poop.updateHitbox();
				return;
			}
			LuaShared.luaTrace('scaleObject: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});

		addCallback("updateHitbox", function(obj:String) {
			if(LuaUtils.getLuaObject(obj)!=null) {
				var shit:FlxSprite = LuaUtils.getLuaObject(obj);
				shit.updateHitbox();
				return;
			}

			var split:Array<String> = obj.split('.');
			var poop:FlxSprite = LuaUtils.resolveObject(split[0]);
			if(split.length > 1) {
				poop = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(poop != null) {
				poop.updateHitbox();
				return;
			}
			LuaShared.luaTrace('updateHitbox: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});

		addCallback("removeLuaSprite", function(tag:String, destroy:Bool = true, ?group:String = null) {
			var obj:FlxSprite = LuaUtils.resolveObject(tag);
			if(obj == null || obj.destroy == null)
				return;
					
			var groupObj:Dynamic = null;
			if(group == null) groupObj = LuaUtils.getTargetInstance();
			else groupObj = LuaUtils.resolveObject(group);

			groupObj.remove(obj, true);
			if(destroy)
			{
				try {	/////////Remove the tweens too
					var stale:Array<String> = [];
					for (k in getVariables().keys()) {
						if (!k.startsWith('tween_')) continue;
						var tw:Dynamic = getVariables().get(k);
						var owner:Dynamic = null;
						try owner = Reflect.field(tw, '_object') catch (e:Dynamic) {}
						if (owner != null && owner == obj) stale.push(k.substr(6));
					}
					for (k in stale) LuaUtils.cancelTween(k);
				} catch (e:Dynamic) {}
				getVariables().remove(tag);
				obj.destroy();
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

		addCallback("setObjectCamera", function(obj:String, camera:String = 'game') {
			var real:FlxBasic = LuaUtils.getLuaObject(obj);
			if(real != null) {
				real.cameras = [LuaUtils.cameraFromString(camera)];
				if (obj == 'comboGroup') { comboCam = LuaUtils.cameraFromString(camera); LuaCombo.enforceComboCam(funk); }
				return true;
			}

			var split:Array<String> = obj.split('.');
			var object:FlxBasic = LuaUtils.resolveObject(split[0]);
			if(split.length > 1) {
				object = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(object != null) {
				object.cameras = [LuaUtils.cameraFromString(camera)];
				return true;
			}
			LuaShared.luaTrace("setObjectCamera: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});

		addCallback("setBlendMode", function(obj:String, blend:String = '') {
			var real:FlxSprite = LuaUtils.getLuaObject(obj);
			if(real != null) {
				real.blend = LuaUtils.blendModeFromString(blend);
				return true;
			}

			var split:Array<String> = obj.split('.');
			var spr:FlxSprite = LuaUtils.resolveObject(split[0]);
			if(split.length > 1) {
				spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(spr != null) {
				spr.blend = LuaUtils.blendModeFromString(blend);
				return true;
			}
			LuaShared.luaTrace("setBlendMode: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});

		addCallback("screenCenter", function(obj:String, pos:String = 'xy') {
			var spr:FlxObject = LuaUtils.getLuaObject(obj);

			if (spr == null) {
				var split:Array<String> = obj.split('.');
				spr = LuaUtils.resolveObject(split[0]);
				if (split.length > 1) {
					spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
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
			LuaShared.luaTrace("screenCenter: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
		});

		addCallback("setObjectOrder", function(obj:String, position:Int, ?group:String = null) {
			var leObj:Dynamic = LuaUtils.getLuaObject(obj);
			if (leObj == null) leObj = LuaUtils.resolveObject(obj);
			if (leObj != null) {
				var groupObj:Dynamic = null;
				if (group != null) {
					groupObj = LuaUtils.getProperty(group);
					if (groupObj == null) {
						LuaShared.luaTrace('setObjectOrder: Group $group doesn\'t exist!');
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
			LuaShared.luaTrace('setObjectOrder: Object $obj doesn\'t exist!');
		});

		addCallback("objectsOverlap", function(obj1:String, obj2:String) {
			var namesArray:Array<String> = [obj1, obj2];
			var objectsArray:Array<FlxBasic> = [];
			for (i in 0...namesArray.length)
			{
				var real:FlxBasic = LuaUtils.getLuaObject(namesArray[i]);
				if(real != null)
					objectsArray.push(real);
				else
					objectsArray.push(Reflect.getProperty(LuaUtils.getTargetInstance(), namesArray[i]));
			}
			return (!objectsArray.contains(null) && FlxG.overlap(objectsArray[0], objectsArray[1]));
		});

		addCallback("getPixelColor", function(obj:String, x:Int, y:Int) {
			var split:Array<String> = obj.split('.');
			var spr:FlxSprite = LuaUtils.resolveObject(split[0]);
			if(split.length > 1) {
				spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(spr != null) return spr.pixels.getPixel32(x, y);
			return FlxColor.BLACK;
		});

		addCallback("startDialogue", function(dialogueFile:String, ?music:String = null) {
			LuaShared.luaTrace('startDialogue: Codename Doesnt Have psych dialogues this will work later.');
			countdownBlocked = false;
			PlayState.instance.startCountdown();
			return false;
		});

		addCallback("startVideo", function(videoFile:Dynamic, ?canSkip:Bool = true, ?forMidSong:Bool = false, ?shouldLoop:Bool = false, ?playOnLoad:Bool = true) {
			return LuaVideos.start(funk, videoFile, canSkip, forMidSong, shouldLoop, playOnLoad);
		});

		addCallback("makeVideoSprite", function(tag:String, video:String, ?ext:String = 'mp4', ?x:Float = 0, ?y:Float = 0, ?loop:Dynamic = false) {
			LuaVideos.make(funk, tag, video, ext, x, y, loop);
		});

		addCallback("setVideoSize", function(tag:String, x:Int, ?y:Int = 0, ?updateHitbox:Bool = true) {
			LuaVideos.setSize(funk, tag, x, y, updateHitbox);
		});

		addCallback("addLuaVideo", function(tag:String, ?front:Bool = false) {
			return LuaVideos.addToState(funk, tag, front);
		});

		addCallback("removeLuaVideo", function(tag:String, ?destroy:Bool = true, ?group:String = null) {
			LuaVideos.remove(funk, tag, destroy, group);
		});

		addCallback("playVideo", function(tag:String) { LuaVideos.play(funk, tag); });
		addCallback("resumeVideo", function(tag:String) { LuaVideos.resume(funk, tag); });
		addCallback("pauseVideo", function(tag:String) { LuaVideos.pause(funk, tag); });
		addCallback("luaVideoExists", function(tag:String) { return LuaVideos.exists(funk, tag); });

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
				if(oldSnd != null){
					oldSnd.stop();
					oldSnd.destroy();
				}
					
				var looped:Bool = loop;

				variables.set(tag, FlxG.sound.play(Paths.sound(sound), volume, loop, null, true, function(){
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
			}else{
				tag = LuaUtils.formatVariable('sound_$tag');
				var variables = getVariables();
				var snd:FlxSound = variables.get(tag);
				if(snd != null){
					snd.stop();
					variables.remove(tag);
				}
			}
		});

		addCallback("pauseSound", function(tag:String) {
			if(tag == null || tag.length < 1){
				if(FlxG.sound.music != null)
					FlxG.sound.music.pause();
			}else{
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
			if(tag == null || tag.length < 1){
				if(FlxG.sound.music != null)
					FlxG.sound.music.fadeIn(duration, fromValue, toValue);
			}else{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = getVariables().get(tag);
				if(snd != null)
					snd.fadeIn(duration, fromValue, toValue);
			}
		});

		addCallback("soundFadeOut", function(tag:String, duration:Float,toValue:Float = 1) {
			if(tag == null || tag.length < 1){
				if(FlxG.sound.music != null)
					FlxG.sound.music.fadeOut(duration, toValue);
			}else{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = getVariables().get(tag);
				if(snd != null)
					snd.fadeOut(duration, toValue);
			}
		});

		addCallback("soundFadeCancel", function(tag:String) {
			if(tag == null || tag.length < 1){
				if(FlxG.sound.music != null && FlxG.sound.music.fadeTween != null)
					FlxG.sound.music.fadeTween.cancel();
			}else{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = getVariables().get(tag);
				if(snd != null && snd.fadeTween != null)
					snd.fadeTween.cancel();
			}
		});

		addCallback("getSoundVolume", function(tag:String) {
			if(tag == null || tag.length < 1)
			{
				if(FlxG.sound.music != null)
					return FlxG.sound.music.volume;
			}
			else
			{
				tag = LuaUtils.formatVariable('sound_$tag');
				var snd:FlxSound = getVariables().get(tag);
				if(snd != null) rezurn snd.volume;
			}
			return 0;
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


		///////////OS ENGINE SHADERS
		addCallback("addChromaticAbberationEffect", function(camera:String, ?chromeOffset:Float = 0.005) {
			LuaEffects.add(funk, camera, 'ChromaticAberration', [['rOffset', chromeOffset], ['gOffset', 0.0], ['bOffset', -chromeOffset]]);
		});
		addCallback("addBlueChromaticAbberationEffect", function(camera:String, ?strength:Float = 0.005) {
			LuaEffects.add(funk, camera, 'ChromAberrationBlueSwap', [['strength', strength]]);
		});
		addCallback("addBarrelBlurAbberationEffect", function(camera:String, ?barrel:Float = 1.0, ?zoom:Float = 1.0, ?doChroma:Bool = false, ?angle:Float = 0.0, ?x:Float = 0.0, ?y:Float = 0.0) {
			LuaEffects.add(funk, camera, 'BarrelBlur', [['barrel', barrel], ['zoom', zoom], ['doChroma', doChroma], ['angle', angle], ['x', x], ['y', y]], 'iTime');
		});
		addCallback("addPixelMosaicEffect", function(camera:String, ?strength:Float = 0.5) {
			LuaEffects.add(funk, camera, 'Pixel', [['Pixelly', strength]], 'iTime');
		});
		addCallback("addMovementBlurEffect", function(camera:String, ?strength:Float = 0.1, ?strengthY:Float = 0.1) {
			LuaEffects.add(funk, camera, 'Blur', [['strength', strength], ['strengthY', strengthY]]);
		});
		addCallback("addSobelEffect", function(camera:String, ?strength:Float = 0.1, ?intensity:Float = 0.1) {
			LuaEffects.add(funk, camera, 'Sobel', [['strength', strength], ['intensity', intensity]]);
		});
		addCallback("addRainEffect", function(camera:String, ?iTime:Float = 20) {
			var w:Float = FlxG.width;
			var h:Float = FlxG.height;
			LuaEffects.add(funk, camera, 'Rain', [
				['uScale', 1.0], ['uIntensity', 0.5], ['uPuddleY', 0.0], ['uPuddleScaleY', 0.0], ['numLights', 0], ['uSpriteMode', false],
				['uRainColor', LuaEffects.hexColor(0xFF6680CC)],
				['uCameraBounds', [0.0, 0.0, w, h]], ['uFrameBounds', [0.0, 0.0, w, h]], ['uScreenResolution', [w, h]]
			], 'uTime', iTime);
		});
		addCallback("addMirrorRepeatEffect", function(camera:String, ?zoom:Float = 1, ?angle:Float = 1, ?iTime:Float = 1, ?x:Float = 1, ?y:Float = 1) {
			LuaEffects.add(funk, camera, 'MirrorRepeat', [['zoom', zoom], ['angle', angle], ['x', x], ['y', y]], 'iTime', iTime);
		});
		addCallback("addHeatEffect", function(camera:String, ?strength:Float = 1, ?iTime:Float = 0) {
			LuaEffects.add(funk, camera, 'Heat', [['strength', strength]], 'iTime', iTime);
		});
		addCallback("addGaussianBlurEffect", function(camera:String, ?loops:Float = 16.0, ?quality:Float = 5.0, ?strength:Float = 20.0) {
			LuaEffects.add(funk, camera, 'BetterBlur', [['loops', loops], ['quality', quality], ['strength', strength]]);
		});
		addCallback("addScanlineEffect", function(camera:String, ?strength:Float = 0.0, ?pixelsBetweenEachLine:Float = 15.0, ?smooth:Bool = false) {
			LuaEffects.add(funk, camera, 'Scanline', [['strength', strength], ['pixelsBetweenEachLine', pixelsBetweenEachLine], ['smoothVar', smooth]]);
		});
		addCallback("addScanlineEffect2", function(camera:String, ?lockAlpha:Bool = false) {
			LuaEffects.add(funk, camera, 'Scanline2', [['lockAlpha', lockAlpha]]);
		});
		addCallback("addVignetteEffect", function(camera:String, ?strength:Float = 1.0, ?size:Float = 0.0, ?red:Float = 0.0, ?green:Float = 0.0, ?blue:Float = 0.0) {
			LuaEffects.add(funk, camera, 'Vignette', [['strength', strength], ['size', size], ['red', red], ['green', green], ['blue', blue]]);
		});
		addCallback("addDistortedNoiseEffect", function(camera:String, ?strength:Float = 1) {
			LuaEffects.add(funk, camera, 'WaveBurst', [['strength', strength]]);
		});
		addCallback("addPerlinSmokeEffect", function(camera:String, ?waveStrength:Float = 1, ?smokeStrength:Float = 1) {
			LuaEffects.add(funk, camera, 'PerlinSmoke', [['waveStrength', waveStrength], ['smokeStrength', smokeStrength]], 'iTime');
		});
		addCallback("addGrainEffect", function(camera:String, ?grainSize:Float = 1.6, ?lumAmount:Float = 1.0, ?coloramount:Float = 0.6, ?lockAlpha:Bool = false) {
			LuaEffects.add(funk, camera, 'Grain', [['grainsize', grainSize], ['lumamount', lumAmount], ['coloramount', coloramount], ['lockAlpha', lockAlpha]], 'uTime', FlxG.random.float(0, 8));
		});
		addCallback("addVCREffect", function(camera:String, ?glitchFactor:Float = 0.0, ?distortion:Bool = true, ?perspectiveOn:Bool = true, ?vignetteMoving:Bool = true) {
			LuaEffects.add(funk, camera, 'VCRDistortion', [
				['vignetteOn', true], ['perspectiveOn', perspectiveOn], ['distortionOn', distortion], ['scanlinesOn', true],
				['vignetteMoving', vignetteMoving], ['glitchModifier', glitchFactor], ['iResolution', [FlxG.width + 0.0, FlxG.height + 0.0, 0.0]]
			], 'iTime');
		});
		addCallback("addGlitchEffect", function(camera:String, ?waveSpeed:Float = 0.1, ?waveFrq:Float = 0.1, ?waveAmp:Float = 0.1) {
			LuaEffects.add(funk, camera, 'Glitch', [['uSpeed', waveSpeed], ['uFrequency', waveFrq], ['uWaveAmplitude', waveAmp]], 'uTime');
		});
		addCallback("addPulseEffect", function(camera:String, ?waveSpeed:Float = 0.1, ?waveFrq:Float = 0.1, ?waveAmp:Float = 0.1) {
			LuaEffects.add(funk, camera, 'Pulse', [['uSpeed', waveSpeed], ['uFrequency', waveFrq], ['uWaveAmplitude', waveAmp], ['uampmul', 1.0], ['uEnabled', true]], 'uTime');
		});
		addCallback("addDistortionEffect", function(camera:String, ?waveSpeed:Float = 0.1, ?waveFrq:Float = 0.1, ?waveAmp:Float = 0.1) {
			LuaEffects.add(funk, camera, 'DistortBG', [['uSpeed', waveSpeed], ['uFrequency', waveFrq], ['uWaveAmplitude', waveAmp]], 'uTime');
		});
		addCallback("addBlockedEffect", function(camera:String, ?res:Float = 16, ?time:Float = 0, ?colorMultiplier:Float = 1, ?colorTransform:Bool = false) {
			LuaEffects.add(funk, camera, 'BlockedGlitch', [['enabled', true], ['end', 0.0], ['screenSize', [res, res]]], 'time', time);
		});
		addCallback("addInvertEffect", function(camera:String, ?lockAlpha:Bool = false) {
			LuaEffects.add(funk, camera, 'Invert', []);
		});
		addCallback("addStaticEffect", function(camera:String, ?strength:Float = 10) {
			LuaEffects.add(funk, camera, 'Static', [['strength', strength]], 'iTime');
		});
		addCallback("addGreyscaleEffect", function(camera:String, ?iStrength:Float = 10) {
			LuaEffects.add(funk, camera, 'Grey2', [['iStrength', iStrength]]);
		});
		addCallback("addGrayscaleEffect", function(camera:String) {
			LuaEffects.add(funk, camera, 'Greyscale', []);
		});
		addCallback("addBloomEffect", function(camera:String, ?effect:Float = 5, ?strength:Float = 0.2, ?contrast:Float = 1.0, ?brightness:Float = 0.0) {
			LuaEffects.add(funk, camera, 'Bloom', [['effect', effect], ['strength', strength], ['contrast', contrast], ['brightness', brightness], ['iResolution', [FlxG.width + 0.0, FlxG.height + 0.0]]]);
		});
		addCallback("addBloomEffect2", function(camera:String, ?intensity:Float = 0.35, ?blurSize:Float = 1.0) {
			LuaEffects.add(funk, camera, 'Bloom2', [['intensity', intensity], ['blurSize', blurSize / 512.0]]);
		});

		addCallback("addPsych3DEffect", function(camera:String, ?xrot:Float = 0, ?yrot:Float = 0, ?zrot:Float = 0, ?xpos:Float = 0, ?ypos:Float = 0, ?dept:Float = 0) {
			LuaEffects.add(funk, camera, 'Psych3D', [['_active', true], ['xrot', xrot], ['yrot', yrot], ['zrot', zrot], ['xpos', xpos], ['ypos', ypos], ['dept', dept]]);
		});
		addCallback("addDropShadowEffect", function(camera:String, ?angle:Float = 90, ?distance:Float = 15, ?strength:Float = 1, ?threshold:Float = 0.1, ?color:Dynamic = 'FFDFEF3C', ?antialias:Float = 2, ?zoom:Float = 1) {
			LuaEffects.add(funk, camera, 'DropShadowScreenspace', [
				['ang', angle * Math.PI / 180], ['dist', distance], ['str', strength], ['thr', threshold], ['thr2', 0.0], ['useMask', false],
				['dropColor', LuaEffects.hexColor(color, 0xFFDFEF3C)], ['hue', 0.0], ['saturation', 0.0], ['brightness', 0.0], ['contrast', 0.0],
				['AA_STAGES', antialias], ['zoom', zoom], ['angOffset', 0.0], ['uFrameBounds', [0.0, 0.0, 1.0, 1.0]]
			]);
		});
		addCallback("addGrayscaleAmountEffect", function(camera:String, ?amount:Float = 1) {
			LuaEffects.add(funk, camera, 'grayscale', [['_amount', amount]]);
		});

		addCallback("doBloomPulse", function(camera:String, ?intensityFrom:Float = 0.5, ?length:Float = 0.25, ?ease:String = 'linear') {
			var e:Dynamic = LuaEffects.find(funk, camera, 'Bloom2');
			if (e != null) LuaEffects.pulse(function(v:Float) { try e.shader.hset('intensity', v) catch (x:Dynamic) {} }, intensityFrom, length, ease);
		});
		addCallback("doChromaticPulse", function(camera:String, ?newOffset:Float = 0.03, ?length:Float = 0.25, ?ease:String = 'linear') {
			var e:Dynamic = LuaEffects.find(funk, camera, 'ChromaticAberration');
			if (e == null) e = LuaEffects.add(funk, camera, 'ChromaticAberration', [['rOffset', 0.0], ['gOffset', 0.0], ['bOffset', 0.0]]);
			if (e != null) LuaEffects.pulse(function(v:Float) {
				try { e.shader.hset('rOffset', v); e.shader.hset('gOffset', 0.0); e.shader.hset('bOffset', -v); } catch (x:Dynamic) {}
			}, newOffset, length, ease);
		});
		addCallback("clearEffects", function(camera:String) {
			var c:Dynamic = LuaEffects.camOf(funk, camera);
			for (e in LuaEffects.active.copy()) if (e.cam == c) LuaEffects.remove(e);
		});

		addCallback("removeEffect", function(camera:String, ?effect:Dynamic = null) {
			var c:Dynamic = LuaEffects.camOf(funk, camera);
			var last:Dynamic = null;
			for (e in LuaEffects.active) if (e.cam == c && (effect == null || !Std.isOfType(effect, String) || e.kind == effect)) last = e;
			if (last != null) LuaEffects.remove(last);
		});

		addCallback("makeLuaShaderSprite", function(tag:String, shader:String, x:Float, y:Float, ?optimize:Bool = false) {
			tag = tag.replace('.', '');
			LuaUtils.destroyObject(tag);
			var spr:ModchartSprite = new ModchartSprite(x, y);
			spr.active = true;
			try {
				spr.makeGraphic(FlxG.width, FlxG.height, 0xFFFFFFFF);
				if (LuaShared.opt(['gameplayShaders', 'shaders'], true) && LuaShaders.initLuaShader(funk, shader)) {
					var sh:Dynamic = new CustomShader(shader);
					spr.shader = sh;
					funk.objShaders.set(tag, sh);
					if (!optimize) {
						LuaEffects.timed.push({cam: null, kind: shader, shader: sh, timeUniform: 'iTime', t: 0.0});
						LuaEffects.hook();
					}
				}
			} catch (e:Dynamic) LuaShared.luaTrace('makeLuaShaderSprite: ' + Std.string(e));
			LuaShared.variables.set(tag, spr);
		});

		////////////////////TWEEN
		addCallback("startTween", function(tag:String, vars:String, values:Dynamic, duration:Float, ?options:Dynamic = null) {
			var target:Dynamic = LuaTweens.tweenPrepare(funk, tag, vars);
			if (target == null) {
				LuaShared.luaTrace('startTween: Couldnt find object: ' + vars, false, false, FlxColor.RED);
				return null;
			}
			if (values == null) {
				LuaShared.luaTrace('startTween: No values on 2nd argument!', false, false, FlxColor.RED);
				return null;
			}

			var getOpt:String->Dynamic = function(name:String):Dynamic {
				return (options != null && Reflect.hasField(options, name)) ? Reflect.field(options, name) : null;
			};
			var twnType:FlxTweenType = LuaTweens.tweenTypeFromString(funk, getOpt('type'));
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
			var vars:String = vars;
			var variables = getVariables();
			var key:String = null;
			if (tag != null) key = LuaUtils.formatVariable('tween_' + tag);

			var tw:FlxTween = FlxTween.tween(target, values, duration, {
				type: twnType,
				ease: LuaUtils.getTweenEaseByString(easeName == null ? 'linear' : easeName),
				startDelay: startDelay,
				loopDelay: loopDelay,
				onUpdate: function(twn:FlxTween) {
					if (onUpdateName != null) LuaShared.callOnAll(onUpdateName, [originalTag, vars]);
				},
				onStart: function(twn:FlxTween) {
					if (onStartName != null) LuaShared.callOnAll(onStartName, [originalTag, vars]);
				},
				onComplete: function(twn:FlxTween) {
					var looping:Bool = twn.type == 2 || twn.type == 4;
					if (key != null && (twn.type == 8 || twn.type == 16)) variables.remove(key);
					if (onCompleteName != null) LuaShared.callOnAll(onCompleteName, [originalTag, vars]);
					if (originalTag != null && !looping) LuaShared.callOnAll('onTweenCompleted', [originalTag, vars]);
				}
			});
			if (key != null) {
				variables.set(key, tw);
				return key;
			}
			return null;
		});

		addCallback("doTweenX", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return LuaTweens.oldTweenFunction(funk, tag, vars, {x: value}, duration, ease, 'doTweenX');
		});

		addCallback("doTweenY", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return LuaTweens.oldTweenFunction(funk, tag, vars, {y: value}, duration, ease, 'doTweenY');
		});

		addCallback("doTweenAngle", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return LuaTweens.oldTweenFunction(funk, tag, vars, {angle: value}, duration, ease, 'doTweenAngle');
		});

		addCallback("doTweenAlpha", function(tag:String, vars:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return LuaTweens.oldTweenFunction(funk, tag, vars, {alpha: value}, duration, ease, 'doTweenAlpha');
		});

		addCallback("doTweenZoom", function(tag:String, camera:String, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			var camKey:String = camera;
			switch (camera.toLowerCase()) {
				case 'camgame' | 'game':
					camKey = 'camGame';
				case 'camhud' | 'hud':
					camKey = 'camHUD';
				case 'camother' | 'other':
					camKey = 'camOther';
					if (getVariables().get('camOther') == null)
						getVariables().set('camOther', FlxG.cameras.list[FlxG.cameras.list.length - 1]);
				default:
					var cam:FlxCamera = getVariables().get(camera);
					if (cam == null || !Std.isOfType(cam, FlxCamera)) camKey = 'camGame';
			}
			return LuaTweens.oldTweenFunction(funk, tag, camKey, {zoom: value}, duration, ease, 'doTweenZoom');
		});

		addCallback("doTweenColor", function(tag:String, vars:String, targetColor:String, duration:Float, ?ease:String = 'linear') {
			var penisExam:Dynamic = LuaTweens.tweenPrepare(funk, tag, vars);
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

							LuaShared.callOnAll('onTweenCompleted', [originalTag, thevars]);
						}
					}));
					return tag;
				}
				else FlxTween.color(penisExam, duration, curColor, CoolUtil2.colorFromString(targetColor), {ease: LuaUtils.getTweenEaseByString(ease)});
			}
		else LuaShared.luaTrace('doTweenColor: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			return null;
		});

		addCallback("cancelTween", function(tag:String) {
			LuaTweens.cancelTweenSafe(funk, tag);
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
			return FunkinLua.startLuaTimer(tag, time, loops);
		});

		addCallback("runtimer", function(tag:String, time:Float = 1, loops:Int = 1) {
			return FunkinLua.startLuaTimer(tag, time, loops);
		});

		addCallback("cancelTimer", function(tag:String) {
			FunkinLua.cancelTimerSafe(tag);
		});

		//////////Playstate
		addCallback("addScore", function(value:Int = 0) {
			PlayState.instance.songScore += value;
			//game.RecalculateRating();
		});

		addCallback("addMisses", function(value:Int = 0) {
			PlayState.instance.misses += value;
			LuaCombo.refreshRating(funk);
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
			LuaCombo.refreshRating(funk);
		});
		addCallback("setHealth", function(value:Float = 1) { PlayState.instance.health = value; });

		addCallback("addHealth", function(value:Float = 0) { PlayState.instance.health += value; });

		addCallback("getHealth", function() {
			return PlayState.instance.health; 
		});

		addCallback("getScore", function() { return PlayState.instance.songScore; });
		addCallback("getMisses", function() { return PlayState.instance.misses; });
		addCallback("getHits", function() { return LuaShared.hits; });
		addCallback("getCombo", function() { return PlayState.instance.combo; });
		addCallback("getRatingPercent", function() { return LuaCombo.ratingPercentValue(funk); });

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
				LuaShared.luaTrace('precacheImage: ' + Std.string(e));
			}
		});

		addCallback("precacheSound", function(name:String) {
			try {
				Assets.getSound(Paths.sound(name));
			} catch (e:Dynamic) {
				LuaShared.luaTrace('precacheSound: ' + Std.string(e));
			}
		});

		addCallback("precacheMusic", function(name:String) {
			try {
				Assets.getSound(Paths.music(name));
			} catch (e:Dynamic) {
				LuaShared.luaTrace('precacheMusic: ' + Std.string(e));
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
			LuaShaders.safeCam(funk, camera).shake(intensity, duration);
		});

		addCallback("cameraFlash", function(camera:String, color:String, duration:Float, ?forced:Bool = false) {
			LuaShaders.safeCam(funk, camera).flash(CoolUtil2.colorFromString(color), duration, null, forced);
		});

		addCallback("cameraFade", function(camera:String, color:String, duration:Float, ?forced:Bool = false, ?fadeOut:Bool = false) {
			LuaShaders.safeCam(funk, camera).fade(CoolUtil2.colorFromString(color), duration, fadeOut, null, forced);
		});

		//////////////////
		addCallback("getMouseX", function(?camera:String = 'game') {
			var cam:FlxCamera = LuaShaders.safeCam(funk, camera);
			return FlxG.mouse.getScreenPosition(cam).x;
		});

		addCallback("getMouseY", function(?camera:String = 'game') {
			var cam:FlxCamera = LuaShaders.safeCam(funk, camera);
			return FlxG.mouse.getScreenPosition(cam).y;
		});

		addCallback("getMidpointX", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = LuaProps.resolveObject(funk, split[0]);
			if(split.length > 1) {
				obj = LuaProps.getVarInArray(funk, LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return LuaProps.psychMid(funk, obj, true);
			return 0;
		});

		addCallback("getMidpointY", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = LuaProps.resolveObject(funk, split[0]);
			if(split.length > 1) {
				obj = LuaProps.getVarInArray(funk, LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return LuaProps.psychMid(funk, obj, false);
			return 0;
		});

		addCallback("getGraphicMidpointX", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxSprite = LuaProps.resolveObject(funk, split[0]);
			if(split.length > 1) {
				obj = LuaProps.getVarInArray(funk, LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}
			if(obj != null) return obj.getGraphicMidpoint().x;
			return 0;
		});

		addCallback("getGraphicMidpointY", function(variable:String) {
			var split:Array<String> = variable.split('.');
			var obj:FlxSprite = LuaProps.resolveObject(funk, split[0]);
			if(split.length > 1) {
				obj = LuaProps.getVarInArray(funk, LuaUtils.getPropertyLoop(split), split[split.length-1]);	
			}
			if(obj != null) return obj.getGraphicMidpoint().y;
			return 0;
		});

		addCallback("getScreenPositionX", function(variable:String, ?camera:String = 'game') {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = LuaProps.resolveObject(funk, split[0]);
			if(split.length > 1) {
				obj = LuaProps.getVarInArray(funk, LuaUtils.getPropertyLoop(split), split[split.length-1]);	
			}
			if(obj != null) return obj.getScreenPosition(LuaShaders.safeCam(funk, camera)).x;
			return 0;
		});

		addCallback("getScreenPositionY", function(variable:String, ?camera:String = 'game') {
			var split:Array<String> = variable.split('.');
			var obj:FlxObject = LuaProps.resolveObject(funk, split[0]);
			if(split.length > 1) {
				obj = LuaProps.getVarInArray(funk, LuaUtils.getPropertyLoop(split), split[split.length-1]);	
			}
			if(obj != null) return obj.getScreenPosition(LuaShaders.safeCam(funk, camera)).y;
			return 0;
		});

		addCallback("characterDance", function(character:String) {
			var c:Dynamic = LuaProps.getChar(funk, character);
			if (c != null && Std.isOfType(c, Character)) {
				var ch:Character = cast c;
				ch.dance();
			}
		});



		////////////////sound

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
			if (variable == 'videoCutscene') return videoSprite != null ? true : null;
			return LuaProps.getProperty(funk, variable, allowMaps);
		});

		addCallback("setProperty", function(variable:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false) {
			LuaProps.setProperty(funk, variable, value, allowMaps, allowInstances);
		});

		addCallback("getPropertyFromClass", function(classVar:String, variable:String, ?allowMaps:Bool = false) {
			if (classVar != null && (classVar.startsWith('ClientPrefs.') || classVar.startsWith('Options.'))) return null;
			if (classVar == 'backend.Mods' || classVar == 'Mods') {
				if (variable == 'currentModDirectory') {
					var cm:String = ModsFolder.currentModFolder;
					return cm == null ? '' : cm;
				}
				if (variable == 'mergeAllTextsNamed' || variable == 'getGlobalMods' || variable == 'getModDirectories') return [];
				LuaShared.luaTrace('getPropertyFromClass: Mods.' + variable + ' does not exist in Codename (returning nil)', false, false, FlxColor.YELLOW);
				return null;
			}
			var ckg:String = LuaCombo.comboAliasKey(funk, variable);
			if (ckg != null && LuaCombo.isPrefsClass(funk, classVar)) return LuaCombo.getComboOption(funk, ckg);
			if (LuaCombo.isPrefsClass(funk, classVar)) {
				var coi:Int = LuaCombo.comboOffsetIndex(funk, variable);
				if (coi == -2) return [LuaCombo.getComboOffset(funk, 0), LuaCombo.getComboOffset(funk, 1), LuaCombo.getComboOffset(funk, 2), LuaCombo.getComboOffset(funk, 3)];
				if (coi >= 0) return LuaCombo.getComboOffset(funk, coi);
			}
			if (LuaCombo.isPrefsClass(funk, classVar)) {
				var raw:String = variable.startsWith('data.') ? variable.substr(5) : variable;
				var field:String = LuaCombo.prefsField(funk, variable);
				if (Type.getClassFields(Options).contains(field)) return LuaProps.getPath(funk, Options, field, allowMaps);
				if (LuaCombo.prefsDefaults.exists(raw)) return LuaCombo.prefsDefaults.get(raw);
				LuaShared.luaTrace('getPropertyFromClass: option ' + raw + ' does not exist in Codename (returning nil)', false, false, FlxColor.YELLOW);
				return null;
			}
			var myClass:Dynamic = LuaProps.resolveClassByName(funk, classVar);
			if (myClass == null) {
				LuaShared.luaTrace('getPropertyFromClass: Class ' + classVar + ' not found');
				return null;
			}
			var resC:Dynamic = LuaProps.getPath(funk, myClass, variable, allowMaps);
			if (resC == null) {
				var fbC:Dynamic = LuaProps.numericFallback(funk, classVar + '.' + variable);
				if (fbC != null) return fbC;
			}
			return resC;
		});

		addCallback("setPropertyFromClass", function(classVar:String, variable:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false) {
			if (classVar != null && (classVar.startsWith('ClientPrefs.') || classVar.startsWith('Options.'))) {
				if (classVar.endsWith('.keyBinds') || classVar.endsWith('.keybinds')) return;
				LuaShared.luaTrace('setPropertyFromClass: ' + classVar + ' does not exist in Codename (ignored)', false, false, FlxColor.YELLOW);
				return;
			}
			var cks:String = LuaCombo.comboAliasKey(funk, variable);
			if (cks != null && LuaCombo.isPrefsClass(funk, classVar)) { LuaCombo.setComboOption(funk, cks, value); return; }
			if (LuaCombo.isPrefsClass(funk, classVar)) {
				var coi:Int = LuaCombo.comboOffsetIndex(funk, variable);
				if (coi == -2 && Std.isOfType(value, Array)) {
					var arr:Array<Dynamic> = value;
					for (k in 0...Std.int(Math.min(4, arr.length))) LuaCombo.setComboOffset(funk, k, arr[k]);
					return;
				}
				if (coi >= 0) { LuaCombo.setComboOffset(funk, coi, value); return; }
			}
			if (LuaCombo.isPrefsClass(funk, classVar)) {
				var fieldS:String = LuaCombo.prefsField(funk, variable);
				if (Type.getClassFields(Options).contains(fieldS)) LuaProps.setPath(funk, Options, fieldS, LuaProps.parseInstance(funk, value, allowInstances), allowMaps);
				else LuaShared.luaTrace('setPropertyFromClass: option ' + variable + ' does not exist in Codename (ignored)', false, false, FlxColor.YELLOW);
				return;
			}
			var myClass:Dynamic = LuaProps.resolveClassByName(funk, classVar);
			if (myClass == null) {
				LuaShared.luaTrace('setPropertyFromClass: Class ' + classVar + ' not found');
				return;
			}
			LuaProps.setPath(funk, myClass, variable, LuaProps.parseInstance(funk, value, allowInstances), allowMaps);
		});

		addCallback("getPropertyFromGroup", function(group:String, index:Int, variable:String, ?allowMaps:Bool = false) {
			var obj:Dynamic = LuaProps.groupMember(funk, group, index);
			if (obj == null) return null;
			var resG:Dynamic = LuaProps.getPath(funk, obj, variable, allowMaps);
			if (resG == null) { var fbG:Dynamic = LuaProps.numericFallback(funk, group + '.' + variable); if (fbG != null) return fbG; }
			return resG;
		});

		addCallback("setPropertyFromGroup", function(group:String, index:Int, variable:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false) {
			var obj:Dynamic = LuaProps.groupMember(funk, group, index);
			if (obj == null) return;
			LuaProps.setPath(funk, obj, variable, LuaProps.parseInstance(funk, value, allowInstances), allowMaps);
		});

		///////// SCRIPTS
		addCallback("getRunningScripts", function() {
			var r:Array<String> = [];
			for (s in all) r.push(s.scriptName);
			return r;
		});

		addCallback("setOnScripts", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null) {
			LuaShared.setOnAll(varName, arg, LuaShared.withSelf(funk, exclusions, ignoreSelf));
			try PlayState.instance.scripts.set(varName, arg) catch (e:Dynamic) {}
		});
		addCallback("setOnLuas", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null) {
			LuaShared.setOnAll(varName, arg, LuaShared.withSelf(funk, exclusions, ignoreSelf));
		});
		addCallback("setOnHScript", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null) {
			try PlayState.instance.scripts.set(varName, arg) catch (e:Dynamic) {}
		});

		addCallback("callOnLuas", function(funcName:String, ?args:Array<Dynamic> = null, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String> = null, ?excludeValues:Array<Dynamic> = null) {
			return LuaShared.callOnAll(funcName, args, ignoreStops, LuaShared.withSelf(funk, excludeScripts, ignoreSelf), excludeValues);
		});
		addCallback("callOnScripts", function(funcName:String, ?args:Array<Dynamic> = null, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String> = null, ?excludeValues:Array<Dynamic> = null) {
			if (args == null) args = [];
			if (excludeValues == null) excludeValues = [Function_Continue];
			var r:Dynamic = LuaShared.callOnAll(funcName, args, ignoreStops, LuaShared.withSelf(funk, excludeScripts, ignoreSelf), excludeValues);
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
			var path:String = LuaFiles.findScript(funk, luaFile);
			if (path != null)
				for (s in all)
					if (!s.closed && FunkinLua.sameScript(s.scriptName, path)) return s.call(funcName, args == null ? [] : args);
			return null;
		});

		addCallback("isRunning", function(scriptFile:String) {
			var path:String = LuaFiles.findScript(funk, scriptFile);
			if (path != null)
				for (s in all)
					if (!s.closed && FunkinLua.sameScript(s.scriptName, path)) return true;
			var hpath:String = LuaFiles.findScript(funk, scriptFile, '.hx');
			if (hpath != null) {
				try {
					for (s in PlayState.instance.scripts.scripts)
						if (s.path == hpath) return true;
				} catch (e:Dynamic) {}
			}
			return false;
		});

		addCallback("addLuaScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false) {
			var path:String = LuaFiles.findScript(funk, luaFile);
			if (path == null) { LuaShared.luaTrace("addLuaScript: Script doesn't exist!"); return; }
			if (!ignoreAlreadyRunning)
				for (s in all)
					if (s.scriptName == path) { LuaShared.luaTrace('addLuaScript: The script "' + path + '" is already running!'); return; }
			allowDuplicate = ignoreAlreadyRunning == true;
			new FunkinLua(path);
			allowDuplicate = false;
		});

		addCallback("removeLuaScript", function(luaFile:String) {
			var path:String = LuaFiles.findScript(funk, luaFile);
			var found:Bool = false;
			if (path != null)
				for (s in all.copy())
					if (s.scriptName == path) { s.stop(); found = true; }
			if (!found) LuaShared.luaTrace("removeLuaScript: Script " + luaFile + " isn't running!");
			return found;
		});

		addCallback("addHScript", function(scriptFile:String, ?ignoreAlreadyRunning:Bool = false) {
			var path:String = LuaFiles.findScript(funk, scriptFile, '.hx');
			if (path == null) { LuaShared.luaTrace("addHScript: Script doesn't exist!"); return; }
			try PlayState.instance.scripts.importScript(path) catch (e:Dynamic) LuaShared.luaTrace('addHScript: ' + Std.string(e));
		});

		addCallback("removeHScript", function(scriptFile:String) {
			var path:String = LuaFiles.findScript(funk, scriptFile, '.hx');
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
			if (!found) LuaShared.luaTrace("removeHScript: Script " + scriptFile + " isn't running!");
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
			LuaShared.luaTrace("getModSetting: Codename Engine no tiene mod settings de Psych.");
			return null;
		});

		///////// SPRITES
		addCallback("loadGraphic", function(variable:String, image:String, ?gridX:Int = 0, ?gridY:Int = 0) {
			var spr:Dynamic = LuaProps.getProperty(funk, variable);
			if (spr == null) spr = LuaProps.resolveObject(funk, variable);
			if (spr != null && image != null && image.length > 0)
				spr.loadGraphic(Paths.image(image), gridX != 0 || gridY != 0, gridX, gridY);
		});

		addCallback("loadFrames", function(variable:String, image:String, ?spriteType:String = 'auto') {
			var spr:Dynamic = LuaProps.getProperty(funk, variable);
			if (spr == null) spr = LuaProps.resolveObject(funk, variable);
			if (spr != null && image != null && image.length > 0)
				LuaUtils.loadFrames(spr, image, spriteType);
		});

		addCallback('openURL', function(url:String) {
			CoolUtil2.browserLoad(url);
		});

		addCallback("pcUserName", function() {
			return Sys.environment()["USERNAME"];
		});

		addCallback("loadMultipleFrames", function(variable:String, images:Array<String>) {
			var spr:Dynamic = LuaProps.getProperty(funk, variable);
			if (spr == null) spr = LuaProps.resolveObject(funk, variable);
			if (spr == null || images == null || images.length < 1) return;
			LuaUtils.loadFrames(spr, images[0], 'auto');
			for (i in 1...images.length) {
				try spr.frames.addAtlas(Paths.getSparrowAtlas(images[i])) catch (e:Dynamic) LuaShared.luaTrace('loadMultipleFrames: no se pudo anadir ' + images[i]);
			}
		});

		addCallback("getObjectOrder", function(obj:String, ?group:String = null) {
			var leObj:Dynamic = LuaProps.resolveObject(funk, obj);
			if (leObj == null) { LuaShared.luaTrace("getObjectOrder: Object " + obj + " doesn't exist!"); return -1; }
			var grp:Dynamic = group != null ? LuaProps.getProperty(funk, group) : LuaUtils.getTargetInstance();
			if (grp == null) { LuaShared.luaTrace("getObjectOrder: Group " + group + " doesn't exist!"); return -1; }
			if (Std.isOfType(grp, Array)) return grp.indexOf(leObj);
			var mem:Array<Dynamic> = Reflect.getProperty(grp, 'members');
			var at:Int = mem.indexOf(leObj);
			if (at >= 0) return at;
			for (i in 0...mem.length) if (LuaShared.containsDeep(mem[i], leObj, 0)) return i;
			return mem.length - 1;
		});





		///////// NOTE
		addCallback("noteTweenX", function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return LuaTweens.noteTweenFunction(funk, tag, note, {x: value}, duration, ease);
		});
		addCallback("noteTweenY", function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return LuaTweens.noteTweenFunction(funk, tag, note, {y: value}, duration, ease);
		});
		addCallback("noteTweenAngle", function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return LuaTweens.noteTweenFunction(funk, tag, note, {angle: value}, duration, ease);
		});
		addCallback("noteTweenAlpha", function(tag:String, note:Int, value:Dynamic, duration:Float, ?ease:String = 'linear') {
			return LuaTweens.noteTweenFunction(funk, tag, note, {alpha: value}, duration, ease);
		});
		addCallback("noteTweenDirection", function(tag:String, note:Int, value:Float, duration:Float, ?ease:String = 'linear') {
			return LuaTweens.noteTweenDirectionFunction(funk, tag, note, value, duration, ease);
		});

		///////////PLAYSTATE
		addCallback("addHits", function(?value:Int = 0) {
			LuaShared.hits += value;
			LuaShared.setOnAll('hits', LuaShared.hits);
		});
		addCallback("setHits", function(?value:Int = 0) {
			LuaShared.hits = value;
			LuaShared.setOnAll('hits', LuaShared.hits);
		});

		addCallback("addCharacterToList", function(name:String, type:String) {
			trace('addCharacterToList: ' + name + ' ' + type + ' Codename already did this so...');
		});

		addCallback("triggerEvent", function(name:String, ?value1:Dynamic = '', ?value2:Dynamic = '') {
			try {
				var ev:Dynamic = {name: name, time: Conductor.songPosition, params: [LuaProps.convertEventParam(funk, value1), LuaProps.convertEventParam(funk, value2)]};

				Reflect.setField(ev, '__psych', true);
				Reflect.setField(ev, '__luaDone', false);
				PlayState.instance.executeEvent(ev);

				if (Reflect.field(ev, '__luaDone') != true) {
					Reflect.setField(ev, '__luaDone', true);
					var pv1:Dynamic = ev.params[0];
					var pv2:Dynamic = ev.params[1];
					LuaShared.callOnAll('onEvent', [name, pv1 == null ? '' : Std.string(pv1), pv2 == null ? '' : Std.string(pv2), ev.time]);
				}
				return true;
			} catch (e:Dynamic) {
				LuaShared.luaTrace('triggerEvent: ' + Std.string(e));
			}
			return false;
		});

		addCallback("startCountdown", function() {
			countdownBlocked = false;
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
			if (cls == null) { LuaShared.luaTrace('exitSong: no encontre el menu de destino'); return false; }
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
			var c:Dynamic = LuaProps.getChar(funk, type);
			return c != null ? c.x : 0;
		});
		addCallback("setCharacterX", function(type:String, value:Float) {
			var c:Dynamic = LuaProps.getChar(funk, type);
			if (c != null) c.x = value;
		});
		addCallback("getCharacterY", function(type:String) {
			var c:Dynamic = LuaProps.getChar(funk, type);
			return c != null ? c.y : 0;
		});
		addCallback("setCharacterY", function(type:String, value:Float) {
			var c:Dynamic = LuaProps.getChar(funk, type);
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

		addCallback("setRatingPercent", function(value:Float) { LuaShared.setOnAll('rating', value); });
		addCallback("setRatingName", function(value:String) { LuaShared.setOnAll('ratingName', value); });
		addCallback("setRatingFC", function(value:String) { LuaShared.setOnAll('ratingFC', value); });
		addCallback("setWindowTitle", function(value:String) {Lib.application.window.title = value;});
		addCallback("updateScoreText", function() {});   



		///////// Sound 2
		addCallback("soundFadeOut", function(tag:String, duration:Float, ?toValue:Float = 0) {
			var snd:Dynamic = LuaProps.getSound(funk, tag);
			if (snd != null) snd.fadeOut(duration, toValue);
		});


		addCallback("getSoundTime", function(tag:String) {
			var snd:Dynamic = LuaProps.getSound(funk, tag);
			return snd != null ? snd.time : 0;
		});
		addCallback("setSoundTime", function(tag:String, value:Float) {
			var snd:Dynamic = LuaProps.getSound(funk, tag);
			if (snd != null) snd.time = value;
		});
		addCallback("getSoundPitch", function(tag:String) {
			var snd:Dynamic = LuaProps.getSound(funk, tag);
			return snd != null ? Reflect.getProperty(snd, 'pitch') : 1;
		});
		addCallback("setSoundPitch", function(tag:String, value:Float, ?doPause:Bool = false) {
			var snd:Dynamic = LuaProps.getSound(funk, tag);
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
			LuaProps.setOutline(funk, t, 2, FlxColor.BLACK);
			t.scrollFactor.set();
			getVariables().set(tag, t);
		});

		addCallback("setTextString", function(tag:String, text:Dynamic) {
			var t:FlxText = LuaProps.getText(funk, tag);
			if (t != null) { t.text = Std.string(text); return true; }
			LuaShared.luaTrace("setTextString: Object " + tag + " doesn't exist!");
			return false;
		});
		addCallback("setTextSize", function(tag:String, size:Dynamic) {
			var t:FlxText = LuaProps.getText(funk, tag);
			if (t != null) { t.size = Std.int(size); return true; }
			return false;
		});
		addCallback("setTextWidth", function(tag:String, width:Float) {
			var t:FlxText = LuaProps.getText(funk, tag);
			if (t != null) { t.fieldWidth = width; return true; }
			return false;
		});
		addCallback("setTextHeight", function(tag:String, height:Float) {
			var t:FlxText = LuaProps.getText(funk, tag);
			if (t != null) { t.fieldHeight = height; return true; }
			return false;
		});
		addCallback("setTextAutoSize", function(tag:String, value:Bool) {
			var t:FlxText = LuaProps.getText(funk, tag);
			if (t != null) { t.autoSize = value; return true; }
			return false;
		});
		addCallback("setTextBorder", function(tag:String, size:Float, color:String) {
			var t:FlxText = LuaProps.getText(funk, tag);
			if (t == null) return false;
			if (size > 0) LuaProps.setOutline(funk, t, size, CoolUtil2.colorFromString(color));
			else { var bs:Dynamic = LuaProps.borderStyleOf(funk, 'NONE'); if (bs != null) t.borderStyle = bs; }
			return true;
		});
		addCallback("setTextColor", function(tag:String, color:String) {
			var t:FlxText = LuaProps.getText(funk, tag);
			if (t != null) { t.color = CoolUtil2.colorFromString(color); return true; }
			return false;
		});
		addCallback("setTextFont", function(tag:String, newFont:String) {
			var t:FlxText = LuaProps.getText(funk, tag);
			if (t == null) return false;
			try {
				var f:String = Paths.font(newFont);
				if (!Assets.exists(f)) {
					var alt:String = null;
					for (cand in ['fonts/' + newFont, newFont, 'fonts/' + newFont + '.ttf', 'fonts/' + newFont + '.otf']) {
						alt = LuaFiles.findFile(funk, cand, false);
						if (alt != null) break;
					}
					if (alt != null) f = alt;
				}
				if (Assets.exists(f) || (FileSystem.exists(f) && !FileSystem.isDirectory(f))) t.font = f;
				else LuaShared.luaTrace('setTextFont: font ' + newFont + ' not found (keeping current font)', false, false, FlxColor.YELLOW);
			} catch (e:Dynamic) {
				LuaShared.luaTrace('setTextFont: could not load ' + newFont + ': ' + Std.string(e), false, false, FlxColor.YELLOW);
			}
			return true;
		});
		addCallback("setTextItalic", function(tag:String, italic:Bool) {
			var t:FlxText = LuaProps.getText(funk, tag);
			if (t != null) { t.italic = italic; return true; }
			return false;
		});
		addCallback("setTextAlignment", function(tag:String, ?alignment:String = 'left') {
			var t:FlxText = LuaProps.getText(funk, tag);
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
			var t:FlxText = LuaProps.getText(funk, tag);
			return t != null ? t.text : null;
		});
		addCallback("getTextSize", function(tag:String) {
			var t:FlxText = LuaProps.getText(funk, tag);
			return t != null ? t.size : -1;
		});
		addCallback("getTextFont", function(tag:String) {
			var t:FlxText = LuaProps.getText(funk, tag);
			return t != null ? t.font : null;
		});
		addCallback("getTextWidth", function(tag:String) {
			var t:FlxText = LuaProps.getText(funk, tag);
			return t != null ? t.fieldWidth : 0;
		});
		addCallback("getTextHeight", function(tag:String) {
			var t:FlxText = LuaProps.getText(funk, tag);
			return t != null ? t.height : 0;
		});
		addCallback("addLuaText", function(tag:String, ?inFront:Bool = true) {
			var t:FlxText = LuaProps.getText(funk, tag);
			if (t == null) return;
			var inst:Dynamic = LuaUtils.getTargetInstance();
			if (inst.members.indexOf(t) < 0) inst.add(t);
		});
		addCallback("removeLuaText", function(tag:String, ?destroy:Bool = true) {
			var t:FlxText = LuaProps.getText(funk, tag);
			if (t == null) return;
			LuaUtils.getTargetInstance().remove(t, true);
			if (destroy) { getVariables().remove(tag); t.destroy(); }
		});

		///////// CONTROLS
		addCallback("keyboardJustPressed", function(name:String) { return LuaInput.keyState(funk, 'justPressed', name); });
		addCallback("keyboardPressed", function(name:String) { return LuaInput.keyState(funk, 'pressed', name); });
		addCallback("keyboardReleased", function(name:String) { return LuaInput.keyState(funk, 'justReleased', name); });

		addCallback("keyJustPressed", function(name:String) { return LuaInput.controlState(funk, name, '_P'); });
		addCallback("keyPressed", function(name:String) { return LuaInput.controlState(funk, name, ''); });
		addCallback("keyReleased", function(name:String) { return LuaInput.controlState(funk, name, '_R'); });

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

		addCallback("stringStartsWith", function(str:Dynamic, start:Dynamic) { if (str == null || start == null) return false; return Std.string(str).startsWith(Std.string(start)); });
		addCallback("stringEndsWith", function(str:Dynamic, end:Dynamic) { if (str == null || end == null) return false; return Std.string(str).endsWith(Std.string(end)); });
		addCallback("stringSplit", function(str:Dynamic, split:Dynamic) { if (str == null) return []; return Std.string(str).split(split == null ? '' : Std.string(split)); });
		addCallback("stringTrim", function(str:Dynamic) { if (str == null) return ''; return Std.string(str).trim(); });

		///////// FILES
		addCallback("checkFileExists", function(filename:String, ?absolute:Bool = false) {
			if (absolute != true && LuaCharacters.psychCharXmlPath(funk, filename) != null) return true;
			return LuaFiles.findFile(funk, filename, absolute == true) != null;
		});
		addCallback("getTextFromFile", function(path:String, ?ignoreModFolders:Bool = false) {
			var charJson:String = LuaCharacters.psychCharJson(funk, path);
			if (charJson != null) return charJson;
			var found:String = LuaFiles.findFile(funk, path, false);
			if (found == null) {
				LuaShared.luaTrace('getTextFromFile: cannot find file "' + path + '" (returns nil)', false, false, FlxColor.YELLOW);
				return null;
			}
			try {
				if (FileSystem.exists(found) && !FileSystem.isDirectory(found)) return File.getContent(found);
			} catch (e:Dynamic) {}
			try return Assets.getText(found) catch (e:Dynamic) {}
			return null;
		});
		addCallback("saveFile", function(path:String, content:String, ?absolute:Bool = false) {
			try {
				var full:String = absolute ? path : (modFolder != null ? 'mods/' + modFolder + '/' + path : path);
				var dir:String = full.substr(0, full.lastIndexOf('/'));
				if (dir.length > 0 && !FileSystem.exists(dir)) FileSystem.createDirectory(dir);
				File.saveContent(full, content);
				return true;
			} catch (e:Dynamic) LuaShared.luaTrace('saveFile: ' + Std.string(e));
			return false;
		});
		addCallback("deleteFile", function(path:String, ?ignoreModFolders:Bool = false) {
			try {
				var full:String = (modFolder != null && !ignoreModFolders) ? 'mods/' + modFolder + '/' + path : path;
				if (FileSystem.exists(full)) {
					FileSystem.deleteFile(full);
					LuaFiles.fileCache.clear();
					return true;
				}
			} catch (e:Dynamic) LuaShared.luaTrace('deleteFile: ' + Std.string(e));
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
		addCallback("callMethod", function(funcToRun:String, ?funcArgs:Array<Dynamic> = null):Dynamic {
			if (funcToRun == null) return null;
			if (funcArgs == null) funcArgs = [];
			var dot:Int = funcToRun.lastIndexOf('.');
			var target:Dynamic = dot < 0 ? PlayState.instance : LuaProps.getProperty(funk, funcToRun.substr(0, dot));
			var name:String = dot < 0 ? funcToRun : funcToRun.substr(dot + 1);
			if (target == null) {
				LuaShared.luaTrace('callMethod: object ' + (dot < 0 ? 'PlayState' : funcToRun.substr(0, dot)) + ' not found');
				return null;
			}
			try {
				var pg:Dynamic = PlayState.instance != null ? PlayState.instance.comboGroup : null;
				if (pg != null && target == pg && name == 'setPosition' && funcArgs.length >= 2) {
					funcArgs = [Std.parseFloat(Std.string(funcArgs[0])) + LuaCombo.comboPsychBaseX(funk), Std.parseFloat(Std.string(funcArgs[1])) + LuaCombo.comboPsychBaseY(funk)];
				}
				var fn:Dynamic = Reflect.field(target, name);
				if (fn == null) fn = Reflect.getProperty(target, name);
				if (fn == null || !Reflect.isFunction(fn)) {
					LuaShared.luaTrace('callMethod: ' + name + ' is not a function');
					return null;
				}
				var r:Dynamic = Reflect.callMethod(target, fn, funcArgs);
				return LuaShared.isLuaSupported(r) ? r : null;
			} catch (e:Dynamic) {
				LuaShared.luaTrace('callMethod (' + funcToRun + '): ' + Std.string(e));
			}
			return null;
		});

		addCallback("callMethodFromClass", function(className:String, funcToRun:String, ?funcArgs:Array<Dynamic> = null):Dynamic {
			if (funcArgs == null) funcArgs = [];
			if (className == 'tjson.TJSON' || className == 'TJSON') {
				try {
					if (funcToRun == 'parse' && funcArgs.length > 0 && funcArgs[0] != null)
						return haxe.Json.parse(Std.string(funcArgs[0]));
					if (funcToRun == 'encode' || funcToRun == 'stringify') {
						var style:String = funcArgs.length > 1 ? Std.string(funcArgs[1]) : null;
						return haxe.Json.stringify(funcArgs[0], null, (style == 'fancy') ? '\t' : null);
					}
				} catch (e:Dynamic) {
					LuaShared.luaTrace('callMethodFromClass (TJSON.' + funcToRun + '): ' + Std.string(e));
					return null;
				}
			}
			var cls:Dynamic = LuaProps.resolveClassByName(funk, className);
			if (cls == null) {
				LuaShared.luaTrace('callMethodFromClass: Class ' + className + ' not found');
				return null;
			}
			try {
				var dot:Int = funcToRun.lastIndexOf('.');
				var target:Dynamic = dot < 0 ? cls : LuaProps.getPath(funk, cls, funcToRun.substr(0, dot));
				var name:String = dot < 0 ? funcToRun : funcToRun.substr(dot + 1);
				var fn:Dynamic = Reflect.field(target, name);
				if (fn == null || !Reflect.isFunction(fn)) {
					LuaShared.luaTrace('callMethodFromClass: ' + name + ' is not a function');
					return null;
				}
				var r:Dynamic = Reflect.callMethod(target, fn, funcArgs);
				return LuaShared.isLuaSupported(r) ? r : null;
			} catch (e:Dynamic) {
				LuaShared.luaTrace('callMethodFromClass (' + funcToRun + '): ' + Std.string(e));
			}
			return null;
		});

		addCallback("runHaxeCode", function(codeToRun:String, ?varsToBring:Dynamic = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
			return LuaHaxe.runHaxeCode(funk, codeToRun, varsToBring, funcToRun, funcArgs);
		});

		addCallback("runHaxeFunction", function(funcToRun:String, ?funcArgs:Array<Dynamic> = null):Dynamic {
			if (hscript == null) {
				LuaShared.luaTrace('runHaxeFunction: HScript has not been initialized yet! Use "runHaxeCode" to initialize it');
				return null;
			}
			return LuaHaxe.hscriptCall(funk, funcToRun, funcArgs);
		});

		addCallback("addHaxeLibrary", function(libName:String, ?libPackage:String = '') {
			if (libName == null) libName = '';
			var str:String = (libPackage != null && libPackage.length > 0) ? libPackage + '.' : '';
			var c:Dynamic = Type.resolveClass(str + libName);
			if (c == null) c = Type.resolveEnum(str + libName);
			if (c == null && str.length == 0) c = LuaProps.resolveClassByName(funk, libName);
			if (c == null) {
				LuaShared.luaTrace('addHaxeLibrary: no se encontro ' + str + libName);
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
		addCallback("anyGamepadJustPressed", function(name:String) { return FlxG.gamepads.anyJustPressed(LuaInput.gpId(funk, name)); });
		addCallback("anyGamepadPressed", function(name:String) { return FlxG.gamepads.anyPressed(LuaInput.gpId(funk, name)); });
		addCallback("anyGamepadReleased", function(name:String) { return FlxG.gamepads.anyJustReleased(LuaInput.gpId(funk, name)); });

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
			if (!LuaShared.opt(['gameplayShaders', 'shaders'], true)) {
				LuaShared.luaTrace('initLuaShader: los shaders estan desactivados en las opciones');
				return false;
			}
			return LuaShaders.initLuaShader(funk, name);
		});

		addCallback("setSpriteShader", function(obj:String, shader:String) {
			if (!LuaShared.opt(['gameplayShaders', 'shaders'], true)) { LuaShared.luaTrace('setSpriteShader: los shaders estan desactivados en las opciones'); return false; }
			if (!shaderNames.exists(shader) && !LuaShaders.initLuaShader(funk, shader)) {
				LuaShared.luaTrace('setSpriteShader: Shader $shader is missing!');
				return false;
			}
			var spr:Dynamic = LuaShaders.getShaderTarget(funk, obj);
			if (spr == null) { LuaShared.luaTrace('setSpriteShader: Object $obj not found'); return false; }
			try {
				var sh:Dynamic = new CustomShader(shader);
				if (Std.isOfType(spr, FlxCamera)) {
					LuaShaders.removeShaderFrom(funk, obj, spr);
					spr.addShader(sh);             
				} else {
					spr.shader = sh;
				}
				objShaders.set(obj, sh);            
				return true;
			} catch (e:Dynamic) LuaShared.luaTrace('setSpriteShader: ' + Std.string(e));
			return false;
		});

		addCallback("removeSpriteShader", function(obj:String) {
			var spr:Dynamic = LuaShaders.getShaderTarget(funk, obj);
			if (spr == null) return false;
			LuaShaders.removeShaderFrom(funk, obj, spr);
			if (!Std.isOfType(spr, FlxCamera)) spr.shader = null;
			objShaders.remove(obj);
			return true;
		});

		addCallback("getShaderBool", function(obj:String, prop:String) {
			return LuaShaders.shaderGet(funk, obj, prop, 'getShaderBool');
		});
		addCallback("getShaderBoolArray", function(obj:String, prop:String) {
			return LuaShaders.shaderGet(funk, obj, prop, 'getShaderBoolArray');
		});
		addCallback("getShaderInt", function(obj:String, prop:String) {
			return LuaShaders.shaderGet(funk, obj, prop, 'getShaderInt');
		});
		addCallback("getShaderIntArray", function(obj:String, prop:String) {
			return LuaShaders.shaderGet(funk, obj, prop, 'getShaderIntArray');
		});
		addCallback("getShaderFloat", function(obj:String, prop:String) {
			return LuaShaders.shaderGet(funk, obj, prop, 'getShaderFloat');
		});
		addCallback("getShaderFloatArray", function(obj:String, prop:String) {
			return LuaShaders.shaderGet(funk, obj, prop, 'getShaderFloatArray');
		});

		addCallback("setShaderBool", function(obj:String, prop:String, value:Bool) {
			return LuaShaders.shaderSet(funk, obj, prop, value, 'setShaderBool');
		});
		addCallback("setShaderBoolArray", function(obj:String, prop:String, values:Dynamic) {
			return LuaShaders.shaderSet(funk, obj, prop, values, 'setShaderBoolArray');
		});
		addCallback("setShaderInt", function(obj:String, prop:String, value:Int) {
			return LuaShaders.shaderSet(funk, obj, prop, value, 'setShaderInt');
		});
		addCallback("setShaderIntArray", function(obj:String, prop:String, values:Dynamic) {
			var ints:Array<Dynamic> = [];
			if (values != null) for (v in (values : Array<Dynamic>)) ints.push(Std.int(v));
			return LuaShaders.shaderSet(funk, obj, prop, ints, 'setShaderIntArray');
		});
		addCallback("setShaderFloat", function(obj:String, prop:String, value:Float) {
			return LuaShaders.shaderSet(funk, obj, prop, value, 'setShaderFloat');
		});
		addCallback("setShaderFloatArray", function(obj:String, prop:String, values:Dynamic) {
			return LuaShaders.shaderSet(funk, obj, prop, values, 'setShaderFloatArray');
		});
		addCallback("setShaderSampler2D", function(obj:String, prop:String, bitmapdataPath:String) {
			var s:Dynamic = LuaShaders.getShader(funk, obj, 'setShaderSampler2D');
			if (s == null) return false;
			try {
				var graphic:Dynamic = FlxG.bitmap.add(Paths.image(bitmapdataPath));
				if (graphic != null) {
					try s.hset(prop, graphic.bitmap) catch (e:Dynamic) s.hset(prop, graphic);
					return true;
				}
			} catch (e:Dynamic) {
				LuaShared.luaTrace('setShaderSampler2D: ' + Std.string(e));
			}
			return false;
		});

		load();
	}

	var hscript:Dynamic = null;
	var hscriptLibs:StringMap<Dynamic> = new StringMap<Dynamic>();
	var shaderNames:StringMap<Bool> = new StringMap<Bool>();

	var objShaders:StringMap<Dynamic> = new StringMap<Dynamic>();

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
		if (!closed) {
			frameCb = onFrame;
			FlxG.signals.postUpdate.add(frameCb);
		}
	}

	var frameCb:Void->Void = null;
	var lastScore:Dynamic = null;
	var lastMisses:Dynamic = null;
	var lastCombo:Dynamic = null;
	var lastHealth:Dynamic = null;
	var lastAcc:Dynamic = null;

	var extSeen:StringMap<Bool> = new StringMap<Bool>();
	var fnCache:StringMap<Bool> = new StringMap<Bool>(); 
	var fnCacheTick:Int = 0;
	var syncCache:Array<Dynamic> = [];               
	var inFrame:Bool = false;
	var firstSync:Bool = false;

	var hookedHits:Bool = false;
	var hitHooks:Array<Dynamic> = [];

	function synth(name:String, args:Array<Dynamic>):Void {
		if (extSeen.exists(name)) return;
		var has:Dynamic = fnCache.get(name);
		if (has == null) { has = hasFunction(name); fnCache.set(name, has); }
		if (has != true) return;  
		call(name, args);
	}

	function onFrame():Void {
		if (closed || L == null) return;
		var g:Dynamic = PlayState.instance;
		if (g == null) return;

		if ((fnCacheTick++ % 120) == 0) fnCache.clear();
		inFrame = true;
		if (countdownBlocked) enforceCountdownBlock();
		if (comboCam != null) LuaCombo.enforceComboCam(this);
		try {
			if (!firstSync) {
				firstSync = true;
				LuaGlobals.hookNoteHits(this);
				synth('onCreatePost', []);
				lastScore = g.songScore; lastMisses = g.misses; lastCombo = g.combo;
				lastHealth = g.health; lastAcc = LuaCombo.ratingPercentValue(this);
				synth('onUpdateScore', [false]);
			}

			LuaGlobals.syncGlobals(this);
			synth('onUpdate', [FlxG.elapsed]);

			var score:Dynamic = g.songScore, misses:Dynamic = g.misses, combo:Dynamic = g.combo;
			var health:Dynamic = g.health, acc:Dynamic = LuaCombo.ratingPercentValue(this);

			if (score != lastScore || misses != lastMisses || combo != lastCombo || acc != lastAcc) {
				var missed:Bool = (misses != lastMisses) || (combo == 0 && lastCombo != 0);
				lastScore = score; lastMisses = misses; lastCombo = combo; lastAcc = acc;
				if (!missed) synth('goodNoteHit', [0, 0, '', false]);
				synth('onUpdateScore', [missed]);
			}
			if (health != lastHealth) {
				lastHealth = health;
				if (!hookedHits) synth('opponentNoteHit', [0, 0, '', false]);
			}
			synth('onUpdatePost', [FlxG.elapsed]);
		} catch (e:Dynamic) {}
		inFrame = false;
	}

	public function call(func:String, ?args:Array<Dynamic>):Dynamic {
		if (closed || L == null) return null;
		if (!inFrame) extSeen.set(func, true);
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
		if (func == 'onStartCountdown' && ret != null) {
			var rv:String = Std.string(ret);
			if (rv == Function_Stop || rv == Function_StopAll) {
				var gp:Dynamic = PlayState.instance;
				if (gp != null && gp.startedCountdown != true) {
					countdownBlocked = true;
					countdownBlockOwner = gp;
					Logs.warn('[Lua] onStartCountdown returns Function_Stop in $scriptName');
				}
			}
		}
		if (L != null) Lj.settop(L, top);  
		current = prev;
		return ret;
	}

	public function hasFunction(name:String):Bool {
		if (closed || L == null) return false;
		var top:Int = Lj.gettop(L);
		var r:Bool = false;
		try {
			Lj.getglobal(L, name);
			r = Lj.isfunction(L, -1);
		} catch (e:Dynamic) {}
		Lj.settop(L, top);
		return r;
	}

	public function set(variable:String, value:Dynamic):Void {
		if (closed || L == null) return;
		Lj.setGlobal(L, variable, value);
	}

	public function stop():Void {
		if (closed && L == null) return;
		closed = true;
		if (frameCb != null) { try FlxG.signals.postUpdate.remove(frameCb) catch (e:Dynamic) {} frameCb = null; }
		for (h in hitHooks) { try h.sig.remove(h.cb) catch (e:Dynamic) {} }
		hitHooks = [];
		all.remove(this);
		callbacks.clear();
		if (hscript != null) { try hscript.destroy() catch (e:Dynamic) {} hscript = null; }
		if (L != null) { var s = L; L = null; Lj.close(s); }
	}

	var comboCam:Dynamic = null;

	var comboDbgCount:Int = 0;

	var comboCamArr:Array<FlxCamera> = null;
	var comboSceneTick:Int = 0;

	var warnedNil:StringMap<Bool> = new StringMap<Bool>();

	public function shim_initLuaShader(name:String, ?glslVersion:Dynamic = null):Bool return LuaShaders.shim_initLuaShader(this, name, glslVersion);
	public function shim_createRuntimeShader(name:String, ?glslVersion:Dynamic = null):Dynamic return LuaShaders.shim_createRuntimeShader(this, name, glslVersion);
	public function shim_getLuaObject(tag:String, ?text:Bool = true):Dynamic return LuaShaders.shim_getLuaObject(this, tag, text);
	public function shim_shaderOf(tag:String):Dynamic return LuaShaders.shim_shaderOf(this, tag);
	public function shim_setShaderOf(tag:String, shader:Dynamic):Dynamic return LuaShaders.shim_setShaderOf(this, tag, shader);
	public function shim_camOther():Dynamic return LuaShaders.shim_camOther(this);
	public function shim_filter(shader:Dynamic):Dynamic return LuaShaders.shim_filter(this, shader);

	public static function setOnAll(variable:String, value:Dynamic, ?exclusions:Array<String> = null):Void LuaShared.setOnAll(variable, value, exclusions);
	public static function callOnAll(func:String, ?args:Array<Dynamic> = null, ?ignoreStops:Bool = false, ?exclusions:Array<String> = null, ?excludeValues:Array<Dynamic> = null):Dynamic return LuaShared.callOnAll(func, args, ignoreStops, exclusions, excludeValues);
	public static function setStrumGlobals():Void LuaGlobals.setStrumGlobals();

	function onTweenCompleted(tag:String, vars:String):Void { call('onTweenCompleted', [tag, vars]); }
	function onTimerCompleted(tag:String, loops:Int, loopsLeft:Int):Void { call('onTimerCompleted', [tag, loops, loopsLeft]); }
	function onSoundFinished(tag:String):Void { call('onSoundFinished', [tag]); }
}
