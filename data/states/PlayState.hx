import lua.FunkinLua;
import lua.DebugLuaText;
import lua.helpers.LuaVideos;
import lua.helpers.LuaCombo;
import lua.helpers.LuaHaxe;
import lua.helpers.LuaEffects;

import funkin.game.PlayState;
import funkin.menus.PauseSubState;
import funkin.game.cutscenes.DialogueCutscene;
import funkin.game.GameOverSubstate;
import funkin.backend.scripting.ModSubState;
import flixel.util.FlxTimer;

using StringTools;

var LUA_ROOT:String = 'songs/';

public var luaArray:Array<FunkinLua> = FunkinLua.all;
public var camOther:FlxCamera;
private var luaDebugGroup:FlxTypedGroup<DebugLuaText>;

////////notes var
var __spawnId:Int = 0;
var __hitId:Int = 0;
var __pressedNow:Array<Bool> = [false, false, false, false];
var __hitNow:Array<Bool> = [false, false, false, false];
///////////////////

var __luaReady:Bool = false;      
var __deferredCountdown:Bool = false;
var __seenCb:Array<String> = [];
var __prevCamTarget:Int = 0;

function stopped(r:Dynamic):Bool {
	if (r == null) return false;
	var v:String = Std.string(r);
	return v == FunkinLua.Function_Stop || v == FunkinLua.Function_StopAll;
}

function luaStops(name:String):Bool {
	var stop:Bool = false;
	if (luaArray == null) return false;
	for (script in luaArray.copy()) {
		if (script.closed) continue;
		if (stopped(script.call(name, []))) stop = true;
	}
	return stop;
}

var __blockLogged:Bool = false;

var __wantsSpawn:Bool = true;
var __spawnScanLen:Int = -1;
function __rescanSpawn() {
	__spawnScanLen = luaArray.length;
	__wantsSpawn = false;
	for (script in luaArray)
		if (!script.closed && (script.hasFunction('onSpawnNote') || script.hasFunction('onSpawnNotePost'))) { __wantsSpawn = true; break; }
}

//////////Why this doesnt work?
function __blockNow() {
	if (!__blockLogged) {
		__blockLogged = true;
		trace('[Lua] onStartCountdown return Function_Stop: the song stopped');
	}
	if (startTimer != null && startTimer.active) startTimer.cancel();
	startedCountdown = false;
	if (inst != null && inst.playing) inst.stop();
	if (vocals != null && vocals.playing) vocals.stop();
	for (sl in strumLines.members)
		if (sl.vocals != null && sl.vocals.playing) sl.vocals.stop();
}


function fwd(name:String, ?args:Array<Dynamic>):Dynamic {
	return callOnLuas(name, args);
}

function evToObj(e:Dynamic):Dynamic {
	var o:Dynamic = {__cne: true};
	if (e == null) return o;
	for (f in Reflect.fields(e)) {
		var v = Reflect.field(e, f);
		if (v == null || Std.isOfType(v, Bool) || Std.isOfType(v, Int) || Std.isOfType(v, Float) || Std.isOfType(v, String))
			Reflect.setField(o, f, v);
	}
	return o;
}

function fwdEvent(name:String, e:Dynamic) {
	if (stopped(fwd(name, [evToObj(e)]))) e.cancel();
}

function create() {
	FunkinLua.countdownBlocked = false;
	LuaVideos.videoSprite = null;
	LuaVideos.videoName = null;
	FunkinLua.gamePaused = false;
	__luaFrozen = false;
	__frozenTweens = [];
	__frozenTimers = [];
	__frozenSounds = [];
	__blockLogged = false;
	__charCache = {};
	LuaEffects.reset();
	__lastSectionTarget = -99;
	__camLogCount = 0;
	__followLogCount = 0;

	camOther = new FlxCamera();
	camOther.bgColor = 0x00000000;
	FlxG.cameras.add(camOther, false);

	luaDebugGroup = new FlxTypedGroup<DebugLuaText>();
	luaDebugGroup.cameras = [camOther];
	add(luaDebugGroup);

	FunkinLua.customFunctions.set('openCustomSubstate', function(name:String, ?pause:Bool = false) {
		if (pause) PlayState.instance.persistentUpdate = false;
		PlayState.instance.openSubState(new ModSubState('LuaCustomSubstate', {name: name}));
		return true;
	});
	FunkinLua.customFunctions.set('closeCustomSubstate', function() {
		var sub = PlayState.instance.subState;
		if (sub != null) { sub.close(); return true; }
		return false;
	});
}

function postCreate() {
	loadLuaFolder(LUA_ROOT);

	if (curStage != null) startLuasNamed('stages/' + curStage + '.lua');

	if (gf != null) startCharacterScripts(gf.curCharacter);
	if (dad != null) startCharacterScripts(dad.curCharacter);
	if (boyfriend != null) startCharacterScripts(boyfriend.curCharacter);

	var noteTypes:Array<String> = PlayState.SONG.noteTypes;
	if (noteTypes != null)
		for (notetype in noteTypes)
			if (notetype != null) startLuasNamed('custom_notetypes/' + notetype + '.lua');
	
	__importPsychEvents();

	var seen:Array<String> = [];
	if (PlayState.SONG.events != null)
		for (event in PlayState.SONG.events)
			if (!seen.contains(event.name)) {
				seen.push(event.name);
				startEventLua(event.name);
			}
	loadLuaFolder('songs/' + PlayState.SONG.meta.name + '/scripts/');

	if (PlayState.SONG.events != null)
		for (ev in PlayState.SONG.events) __stringifyLuaEventParams(ev);
	if (PlayState.instance.events != null)
		for (ev in PlayState.instance.events) __stringifyLuaEventParams(ev);
	if (PlayState.SONG.events != null)
		for (ev in PlayState.SONG.events) if (ev != null) Reflect.setField(ev, '__luaDone', false);
	__buildLuaEventQueue();

	if (PlayState.SONG.events != null)
		for (ev in PlayState.SONG.events) {
			if (ev == null || ev.params == null) continue;
			var v1 = ev.params.length > 0 ? __ps(ev.params[0]) : '';
			var v2 = ev.params.length > 1 ? __ps(ev.params[1]) : '';
			var early:Dynamic = callOnLuas('eventEarlyTrigger', [ev.name, v1, v2, ev.time]);
			if (early != null && Std.string(early) != FunkinLua.Function_Continue) {
				var off:Float = Std.parseFloat(Std.string(early));
				if (!Math.isNaN(off) && off != 0) ev.time -= off;
			}
			callOnLuas('onEventPushed', [ev.name, v1, v2, ev.time]);
		}
	__sortEvents();

	if (PlayState.SONG.events != null)
		for (ev in PlayState.SONG.events)
			if (ev != null && ev.name == 'Change Character' && ev.params != null && ev.params.length > 1)
				__makeChar(__charType(__ps(ev.params[0])), __ps(ev.params[1]));

	__camEvents = [];
	if (PlayState.SONG.events == null) return;
	for (ev in PlayState.SONG.events)
		if (ev != null && ev.name == 'Camera Movement' && ev.params != null && ev.params.length > 0) __camEvents.push(ev);
	__camEvents.sort(function(a, b) return a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
	
	__syncSectionGlobals(__camTargetAt(1));
	FunkinLua.setStrumGlobals(); 
	__luaReady = true;
	callOnLuas('onCreatePost');

	if (__deferredCountdown) {
		__deferredCountdown = false;
		if (luaStops('onStartCountdown')) {
			if (!startedCountdown) FunkinLua.countdownBlocked = true;
		} else startCountdown();
	}
}

function loadLua(path:String):Bool {
	for (script in luaArray)
		if (script.scriptName == path) return false;

	var script:FunkinLua = new FunkinLua(path);  
	return !script.closed;                      
}

function loadLuaFolder(folder:String) {
	if (!folder.endsWith('/')) folder += '/';
	for (file in Paths.getFolderContent(folder, false))
		if (file.toLowerCase().endsWith('.lua'))
			loadLua(Paths.getPath(folder + file));
}

public function startLuasNamed(luaFile:String):Bool {
	for (root in [LUA_ROOT, '']) {
		var path:String = Paths.getPath(root + luaFile);
		if (Assets.exists(path)) return loadLua(path);
	}
	return false;
}

var __EVENT_FOLDERS:Array<String> = ['data/events/', 'custom_events/', 'songs/data/events/', 'songs/custom_events/'];
var __eventLuaCache:Dynamic = {};
var __eventLuaIndex:Array<Dynamic> = null;

function __eventVariants(name:String):Array<String> {
	var us:String = name.replace(' ', '_');
	var sp:String = name.replace('_', ' ');
	var out:Array<String> = [name];
	for (v in [us, sp, name.toLowerCase(), us.toLowerCase(), sp.toLowerCase()])
		if (!out.contains(v)) out.push(v);
	return out;
}

function __buildEventLuaIndex() {
	__eventLuaIndex = [];
	for (folder in __EVENT_FOLDERS) {
		try {
			for (file in Paths.getFolderContent(folder, false)) {
				if (!file.toLowerCase().endsWith('.lua')) continue;
				var p:String = Paths.getPath(folder + file);
				var txt:String = null;
				try { txt = Assets.getText(p); } catch (e:Dynamic) {}
				if (txt != null) __eventLuaIndex.push({path: p, text: txt});
			}
		} catch (e:Dynamic) {}
	}
}

function __findEventLua(name:String):String {

	if (Reflect.hasField(__eventLuaCache, name)) return Reflect.field(__eventLuaCache, name);

	var found:String = '';
	var variants:Array<String> = __eventVariants(name);

	for (folder in __EVENT_FOLDERS) {
		for (v in variants) {
			var path:String = Paths.getPath(folder + v + '.lua');
			if (Assets.exists(path)) { found = path; break; }
		}
		if (found != '') break;
	}

	if (found == '') {
		if (__eventLuaIndex == null) __buildEventLuaIndex();
		for (entry in __eventLuaIndex) {
			for (v in variants) {
				var t:String = entry.text;
				if (t.indexOf('== "' + v + '"') >= 0 || t.indexOf("== '" + v + "'") >= 0
					|| t.indexOf('=="' + v + '"') >= 0 || t.indexOf("=='" + v + "'") >= 0) { found = entry.path; break; }
			}
			if (found != '') break;
		}
	}

	Reflect.setField(__eventLuaCache, name, found);
	return found;
}

/////////ps si
function __ps(v:Dynamic):String {
	if (v == null) return '';
	if (Std.isOfType(v, String)) return v;
	if (Std.isOfType(v, Bool) || Std.isOfType(v, Int) || Std.isOfType(v, Float)) return Std.string(v);

	if (v is Array) return [for (x in cast(v, Array<Dynamic>)) __ps(x)].join(',');
	try return haxe.Json.stringify(v) catch (e:Dynamic) {}

	return Std.string(v);
}

function __stringifyLuaEventParams(ev:Dynamic) {
	if (ev == null || ev.name == null) return;
	if (__findEventLua(ev.name) == '') return;

	var out:Array<String> = [];

	if (ev.params != null) for (x in cast(ev.params, Array<Dynamic>)) out.push(__ps(x));
	while (out.length < 2) out.push('');

	ev.params = out;
}

var __eventLogged:Array<String> = [];
function startEventLua(name:String):Bool {
	if (name == null || name == '') return false;
	var path:String = __findEventLua(name);
	var first:Bool = !__eventLogged.contains(name);
	if (first) __eventLogged.push(name);
	if (path == '') {
		if (first) {
			var seen:Array<String> = [];
			for (folder in __EVENT_FOLDERS) {
				try {
					var files:Array<String> = Paths.getFolderContent(folder, false);
					if (files != null && files.length > 0) seen.push(folder + ' [' + files.join(', ') + ']');
				} catch (e:Dynamic) {}
			}
		}
		return false;
	}
	var ok:Bool = loadLua(path);
	return ok;
}

function startCharacterScripts(name:String) {
	if (name != null) startLuasNamed('characters/' + name + '.lua');
}

public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
	if (args == null) args = [];
	if (excludeValues == null) excludeValues = [FunkinLua.Function_Continue];

	var result:Dynamic = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
	if (result == null || excludeValues.contains(result))
		result = scripts.call(funcToCall, args);
	return result;
}

public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
	var returnVal:Dynamic = FunkinLua.Function_Continue;
	if (args == null) args = [];
	if (exclusions == null) exclusions = [];
	if (excludeValues == null) excludeValues = [FunkinLua.Function_Continue];
	if (luaArray == null) return returnVal;

	var closedScripts:Array<FunkinLua> = [];
	for (script in luaArray.copy()) { 
		if (script.closed) { closedScripts.push(script); continue; }
		if (exclusions.contains(script.scriptName)) continue;

		var myValue:Dynamic = script.call(funcToCall, args);
		if ((myValue == FunkinLua.Function_StopLua || myValue == FunkinLua.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops) {
			returnVal = myValue;
			if (script.closed) closedScripts.push(script);
			break;
		}

		if (myValue != null && !excludeValues.contains(myValue))
			returnVal = myValue;

		if (script.closed) closedScripts.push(script);
	}

	for (script in closedScripts) {
		script.stop();       
		luaArray.remove(script);
	}
	return returnVal;
}

public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
	setOnLuas(variable, arg, exclusions);
	scripts.set(variable, arg);
}

public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
	if (exclusions == null) exclusions = [];
	if (luaArray == null) return;
	for (script in luaArray) {
		if (script.closed || exclusions.contains(script.scriptName)) continue;
		script.set(variable, arg);
	}
}

public function addTextToDebug(text:String, color:FlxColor) {
	if (luaDebugGroup == null) { trace(text); return; }

	var newText:DebugLuaText = luaDebugGroup.recycle(DebugLuaText);
	newText.text = text;
	newText.color = color;
	newText.disableTime = 6;
	newText.alpha = 1;
	newText.setPosition(10, 8 - newText.height);

	luaDebugGroup.forEachAlive(function(spr:DebugLuaText) {
		spr.y += newText.height + 2;
	});
	luaDebugGroup.add(newText);

	trace(text);
}
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// PSYCH EVENTS

function __sortEvents() {
	var list = PlayState.instance.events;
	if (list == null) return;
	list.sort(function(a, b) return a.time < b.time ? 1 : (a.time > b.time ? -1 : 0));
}

function __readJson(path:String):Dynamic {
	if (path == null || !Assets.exists(path)) return null;
	try {
		return Json.parse(Assets.getText(path));
	} catch (e:Dynamic) {
		trace('[Lua] Could not parse ' + path + ': ' + Std.string(e));
	}
	return null;
}

function __songNode(raw:Dynamic):Dynamic {
	if (raw == null) return null;
	var s:Dynamic = Reflect.field(raw, 'song');
	if (s != null && !(s is String)) return s;
	return raw;
}

function __num(s:String, def:Float):Float {
	var f:Float = Std.parseFloat(s);
	return Math.isNaN(f) ? def : f;
}

function __importPsychEvents():Int {
	var name:String = PlayState.SONG.meta.name;
	var lists:Array<Dynamic> = [];

	var chart:Dynamic = __songNode(__readJson(Paths.chart(name, PlayState.difficulty, PlayState.variation)));
	if (chart != null && chart.events != null) lists.push(chart.events);

	var extra:Dynamic = __songNode(__readJson(Paths.file('songs/' + name + '/events.json')));
	if (extra != null && extra.events != null) lists.push(extra.events);

	var out:Array<Dynamic> = [];
	for (list in lists) {
		if (!(list is Array)) continue;
		for (entry in cast(list, Array<Dynamic>)) {

			if (!(entry is Array) || entry.length < 2 || !(entry[1] is Array)) continue;
			
			var time:Float = Std.parseFloat(Std.string(entry[0]));
			if (Math.isNaN(time)) continue;

			for (item in cast(entry[1], Array<Dynamic>)) {

				if (!(item is Array) || item.length < 1 || item[0] == null) continue;
				var v1:String = item.length > 1 && item[1] != null ? Std.string(item[1]) : '';
				var v2:String = item.length > 2 && item[2] != null ? Std.string(item[2]) : '';
				out.push({name: Std.string(item[0]), time: time, params: [v1, v2], __psych: true});
			}
		}
	}
	if (out.length == 0) return 0;

	out.reverse();
	if (PlayState.SONG.events == null) PlayState.SONG.events = [];
	for (ev in out) {
		PlayState.SONG.events.push(ev);
		PlayState.instance.events.push(ev);
	}
	__sortEvents();

	trace('[Lua] Imported ' + out.length + ' Psych events');
	return out.length;
}

function __psychChar(who:String, def:Dynamic):Dynamic {
	var w:String = who.toLowerCase().trim();

	if (w == 'bf' || w == 'boyfriend') return boyfriend;
	if (w == 'gf' || w == 'girlfriend') return gf;
	if (w == 'dad' || w == 'opponent') return dad;

	var n:Null<Int> = Std.parseInt(w);

	if (n == 1) return boyfriend;
	if (n == 2) return gf;
	return def;
}

function __setPsychProperty(path:String, raw:String) {
	var t:String = raw.trim();
	var val:Dynamic = t == 'true' ? true : (t == 'false' ? false : (Math.isNaN(Std.parseFloat(raw)) ? raw : Std.parseFloat(raw)));
	var parts:Array<String> = path.trim().split('.');
	var obj:Dynamic = FunkinLua.getVariables().get(parts[0]);
	var start:Int = 1;

	if (obj == null) { obj = PlayState.instance; start = 0; }

	var last:Int = parts.length - 1;
	try {
		for (i in start...last) {
			var nxt:Dynamic = Reflect.getProperty(obj, parts[i]);
			if (nxt == null) { trace('[Lua] "Set Property": ' + parts[i] + ' doesnt exist ' + path); return; }
			obj = nxt;
		}
		if (last < start) { trace('[Lua] "Set Property": ' + path + ' its not a property'); return; }
		Reflect.setProperty(obj, parts[last], val);
	} catch (e:Dynamic) {
		trace('[Lua] ERROR ("Set Property" Event) - ' + Std.string(e));
	}
}

function __shake(cam:FlxCamera, v:String) {
	var sp:Array<String> = v.split(',');
	var duration:Float = sp.length > 0 ? Std.parseFloat(StringTools.trim(sp[0])) : 0;
	var intensity:Float = sp.length > 1 ? Std.parseFloat(StringTools.trim(sp[1])) : 0;
	if (Math.isNaN(duration)) duration = 0;
	if (Math.isNaN(intensity)) intensity = 0;
	if (duration > 0 && intensity != 0) cam.shake(intensity, duration);
}

function __holdAnim(ch:Dynamic, seconds:Float, untilFinished:Bool) {
	if (ch == null) return;
	var wasDancing:Bool = ch.danceOnBeat;
	ch.danceOnBeat = false;
	var waited:Float = 0;
	new FlxTimer().start(0.05, function(tm:FlxTimer) {
		waited += 0.05;
		var done:Bool = seconds > 0 && waited >= seconds;
		if (!done && untilFinished) {
			try { var an = ch.animation.curAnim; done = an == null || an.finished; } catch (e:Dynamic) { done = true; }
		}
		if (done) {
			tm.cancel();
			ch.danceOnBeat = wasDancing;
			try ch.dance() catch (e:Dynamic) {}
		}
	}, 0);
}

var __charCache:Dynamic = {};

function __charType(v:String):Int {
	var w:String = StringTools.trim(v).toLowerCase();
	if (w == 'gf' || w == 'girlfriend') return 2;
	if (w == 'dad' || w == 'opponent') return 1;
	var n:Null<Int> = Std.parseInt(w);
	return (n == null || n < 0 || n > 2) ? 0 : n;
}

function __charSlot(type:Int):Dynamic {
	var idx:Int = type == 0 ? 1 : (type == 1 ? 0 : 2);
	if (strumLines == null || idx >= strumLines.members.length) return null;
	return strumLines.members[idx];
}

function __makeChar(type:Int, name:String):Dynamic {
	var key:String = type + ':' + name;
	if (Reflect.hasField(__charCache, key)) return Reflect.field(__charCache, key);

	var sl:Dynamic = __charSlot(type);
	if (sl == null || name == null || name == '') return null;

	var char:Dynamic = null;
	try {
		var posName:String = (sl.data != null && sl.data.position != null) ? sl.data.position : (type == 0 ? 'boyfriend' : (type == 1 ? 'dad' : 'girlfriend'));
		var playerSide:Bool = sl.data != null ? sl.data.type == 1 : type == 0;
		var flipped:Bool = stage.isCharFlipped(stage.characterPoses[name] != null ? name : posName, playerSide);
		char = new Character(0, 0, name, flipped);
		stage.applyCharStuff(char, posName, 0);
		char.visible = false;
		char.active = false;
	} catch (e:Dynamic) {
		trace('[Lua] Change Character: could no be created "' + name + '": ' + Std.string(e));
		return null;
	}

	Reflect.setField(__charCache, key, char);
	return char;
}

//////////////////////
function __refreshHealthBar() {
	var leftColor:Int = dad != null && dad.iconColor != null && Options.colorHealthBar ? dad.iconColor : (opponentMode ? 0xFF66FF33 : 0xFFFF0000);
	var rightColor:Int = boyfriend != null && boyfriend.iconColor != null && Options.colorHealthBar ? boyfriend.iconColor : (opponentMode ? 0xFFFF0000 : 0xFF66FF33);
	healthBar.createFilledBar(leftColor, rightColor);
	healthBar.updateBar();
}

function __changeCharacter(type:Int, name:String) {
	var sl:Dynamic = __charSlot(type);
	if (sl == null || sl.characters == null || sl.characters.length == 0 || name == '') return;
	var old:Dynamic = sl.characters[0];
	if (old == null) return;
	if (old.curCharacter != name) {
		var char:Dynamic = __makeChar(type, name);
		if (char == null) return;
		Reflect.setField(__charCache, type + ':' + old.curCharacter, old);

		var wasGf:Bool = StringTools.startsWith(old.curCharacter, 'gf-') || old.curCharacter == 'gf';
		char.alpha = old.alpha;
		char.visible = true;
		char.active = true;
		old.visible = false;
		old.active = false;
		sl.characters[0] = char;
		try char.dance() catch (e:Dynamic) {}

		if (type == 1) {
			var nowGf:Bool = StringTools.startsWith(char.curCharacter, 'gf-') || char.curCharacter == 'gf';
			var g:Dynamic = gf;
			if (!nowGf) { if (wasGf && g != null) g.visible = true; }
			else if (g != null) g.visible = false;
		}
		try {
			if (type == 0 && iconP1 != null) iconP1.setIcon(char.getIcon());
			if (type == 1 && iconP2 != null) iconP2.setIcon(char.getIcon());
		} catch (e:Dynamic) {}
	}
	var cur:Dynamic = sl.characters[0];
	if (type == 0) setOnScripts('boyfriendName', cur.curCharacter);
	else if (type == 1) setOnScripts('dadName', cur.curCharacter);
	else setOnScripts('gfName', cur.curCharacter);
	__refreshHealthBar();
}

//////////////Psych events
var __followLogCount:Int = 0;

////////////Restriction
var __PSYCH_ONLY:Array<String> = ['Hey!', 'Set GF Speed', 'Camera Follow Pos', 'Alt Idle Animation', 'Screen Shake', 'Change Character', 'Change Scroll Speed', 'Set Property', 'Play Sound'];

function __psychBuiltin(e:Dynamic, name:String, v1:String, v2:String) {
	var f1:Float = Std.parseFloat(v1);
	var f2:Float = Std.parseFloat(v2);

	if (name == 'Add Camera Zoom') {

		e.cancel();
		if (Options.camZoomOnBeat && camGame.zoom < 1.35) {
			camGame.zoom += Math.isNaN(f1) ? 0.015 : f1;
			camHUD.zoom += Math.isNaN(f2) ? 0.03 : f2;
		}

	} else if (name == 'Play Animation') {

		e.cancel();
		var c:Dynamic = dad;
		var w2:String = StringTools.trim(v2).toLowerCase();
		if (w2 == 'bf' || w2 == 'boyfriend') c = boyfriend;
		else if (w2 == 'gf' || w2 == 'girlfriend') c = gf;
		else {
			var n:Int = Math.isNaN(f2) ? 0 : Math.round(f2);
			if (n == 1) c = boyfriend; else if (n == 2) c = gf;
		}
		if (c != null) {
			c.playAnim(v1, true);
			__holdAnim(c, 0, true);
		}

	} else if (name == 'Camera Follow Pos') {

		if (__followLogCount < 6) { __followLogCount++; trace('[Lua] Camera Follow Pos v1="' + v1 + '" v2="' + v2 + curCameraTarget); }
		if (Math.isNaN(f1) && Math.isNaN(f2)) {
			if (curCameraTarget == -1) { curCameraTarget = __prevCamTarget; moveCamera(); }
		} else {
			if (curCameraTarget >= 0) __prevCamTarget = curCameraTarget;
			curCameraTarget = -1;
			camFollow.setPosition(Math.isNaN(f1) ? 0 : f1, Math.isNaN(f2) ? 0 : f2);
		}

	} else if (name == 'Change Scroll Speed') {

		var finalSpeed:Float = PlayState.SONG.scrollSpeed * (Math.isNaN(f1) ? 1 : f1);
		var duration:Float = Math.isNaN(f2) ? 0 : f2;
		var tw:FlxTween = PlayState.instance.eventsTween.get('scrollSpeedTween');
		if (tw != null) tw.cancel();
		if (duration <= 0) scrollSpeed = finalSpeed;
		else PlayState.instance.eventsTween.set('scrollSpeedTween', FlxTween.tween(PlayState.instance, {scrollSpeed: finalSpeed}, duration, {ease: FlxEase.linear}));

	} else if (name == 'Set GF Speed') {

		var spd:Int = Math.isNaN(f1) ? 1 : Math.round(f1);
		PlayState.instance.gfSpeed = spd < 1 ? 1 : spd;

	} else if (name == 'Hey!') {
		var w:String = StringTools.trim(v1).toLowerCase();
		var who:Int = 2;
	
		if (w == 'bf' || w == 'boyfriend' || w == '0') who = 0;
		else if (w == 'gf' || w == 'girlfriend' || w == '1') who = 1;

		var heyTime:Float = (Math.isNaN(f2) || f2 <= 0) ? 0.6 : f2;

		if (who != 0) {
			var cheerer:Dynamic = (dad != null && StringTools.startsWith(dad.curCharacter, 'gf')) ? dad : gf;
			if (cheerer != null && cheerer.hasAnim('cheer')) { cheerer.playAnim('cheer', true); __holdAnim(cheerer, heyTime, false); }
		}

		if (who != 1 && boyfriend != null && boyfriend.hasAnim('hey')) { boyfriend.playAnim('hey', true); __holdAnim(boyfriend, heyTime, false); }
	} else if (name == 'Screen Shake') {

		__shake(camGame, v1);
		__shake(camHUD, v2);

	} else if (name == 'Alt Idle Animation') {

		var w1:String = StringTools.trim(v1).toLowerCase();
		var ch:Dynamic = dad;
		if (w1 == 'gf' || w1 == 'girlfriend') ch = gf;
		else if (w1 == 'boyfriend' || w1 == 'bf') ch = boyfriend;
		else {
			var val:Null<Int> = Std.parseInt(w1);
			if (val == 1) ch = boyfriend; else if (val == 2) ch = gf;
		}
		if (ch != null) {
			ch.idleSuffix = v2;
			try ch.dance() catch (e:Dynamic) {}
		}

	} else if (name == 'Change Character') {
		__changeCharacter(__charType(v1), v2);
	} else if (name == 'Play Sound') {
		if (v1 != '') FlxG.sound.play(Paths.sound(v1), Math.isNaN(f2) ? 1 : f2);
	} else if (name == 'Set Property') {
		if (v1 != '') __setPsychProperty(v1, v2);
	}
}
var __camEvents:Array<Dynamic> = [];

////////Cur char target
function __camTargetAt(t:Float):Int {
	var target:Int = curCameraTarget >= 0 ? curCameraTarget : 0;
	for (ev in __camEvents) {
		if (ev.time > t) break;
		var v:Float = Std.parseFloat(Std.string(ev.params[0]));
		if (!Math.isNaN(v)) target = Std.int(v);
	}
	return target;
}

var __lastSectionTarget:Int = -99;
var __camLogCount:Int = 0;

function __syncSectionGlobals(target:Int) {
	if (target == __lastSectionTarget) return;
	__lastSectionTarget = target;
	setOnLuas('mustHitSection', target == 1);
	setOnLuas('gfSection', target == 2);
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//CALLBACKS

var __luaEventQueue:Array<Dynamic> = [];
var __skipHold:Float = 0;

function __buildLuaEventQueue() {
	__luaEventQueue = [];
	if (PlayState.SONG.events == null) return;
	for (ev in PlayState.SONG.events)
		if (ev != null && ev.name != null) __luaEventQueue.push(ev);
	__luaEventQueue.sort(function(a, b) return a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
}

function __dispatchLuaEvent(ev:Dynamic, source:String) {
	if (Reflect.field(ev, '__luaDone') == true) return;
	Reflect.setField(ev, '__luaDone', true);
	var p = ev.params;
	var v1:String = (p != null && p.length > 0) ? __ps(p[0]) : '';
	var v2:String = (p != null && p.length > 1) ? __ps(p[1]) : '';
	startEventLua(ev.name);

	fwd('onEvent', [ev.name, v1, v2, ev.time]);
}

function __pollLuaEvents() {
	if (!__luaReady || __luaEventQueue.length == 0 || startingSong || !startedCountdown) return;
	var t:Float = Conductor.songPosition;
	while (__luaEventQueue.length > 0 && __luaEventQueue[0].time <= t)
		__dispatchLuaEvent(__luaEventQueue.shift(), 'cola propia');
}

function update(elapsed:Float) {
	if (FunkinLua.countdownBlocked) __blockNow();

	if (LuaVideos.videoSprite != null && LuaVideos.videoCanSkip && FlxG.keys.pressed.ENTER) {
		__skipHold += elapsed;
		if (__skipHold >= 1) { __skipHold = 0; LuaVideos.stopVideo('skipping'); }
	} else __skipHold = 0;

	__pollLuaEvents();
	callOnLuas('onUpdate', [elapsed]);
}

function onEvent(e) {
	if (e == null || e.event == null) return;
	var p = e.event.params;
	var v1:String = (p != null && p.length > 0) ? __ps(p[0]) : '';
	var v2:String = (p != null && p.length > 1) ? __ps(p[1]) : '';

	if (__luaReady) startEventLua(e.event.name);

	if (Reflect.field(e.event, '__luaDone') != true) __dispatchLuaEvent(e.event, 'hook');
	if (Reflect.field(e.event, '__psych') == true || __PSYCH_ONLY.contains(e.event.name)) __psychBuiltin(e, e.event.name, v1, v2);
}

function onSongStart() {
	fwd('onSongStart');
}

function postUpdate(elapsed:Float) {
	callOnLuas('onUpdatePost', [elapsed]);

	for (k in 0...4) {
		if (__pressedNow[k] && !__hitNow[k] && ghostTapping)
			callOnLuas('onGhostTap', [k]);
		__pressedNow[k] = false;
		__hitNow[k] = false;
	}

	if (luaArray != null && luaArray.length != __spawnScanLen) __rescanSpawn();
	if (__wantsSpawn) {
	var t = Conductor.songPosition;
	for (sl in strumLines.members) {
		var g = sl.notes;
		var m = g.members;
		var i = Std.int(Math.min(g.length, m.length)) - 1;
		var lim = g.limit;
		while (i >= 0) {
			var n = m[i--];
			if (n == null) continue;
			if (n.strumTime > t + lim) break;
			if (n.extra.exists('__luaSpawn')) continue;
			n.extra.set('__luaSpawn', true);
			var a:Array<Dynamic> = [__spawnId++, n.strumID, n.noteType == null ? '' : n.noteType, n.isSustainNote, n.strumTime];
			callOnLuas('onSpawnNote', a);
			callOnLuas('onSpawnNotePost', a);
		}
	}
	}
}

function stepHit(curStep:Int) {
	setOnLuas('curStep', curStep);
	callOnLuas('onStepHit');
}

function beatHit(curBeat:Int) {
	setOnLuas('curBeat', curBeat);
	callOnLuas('onBeatHit');
}

function onStartCountdown(e) {
	if (!__luaReady) { __deferredCountdown = true; e.cancel(); return; }
	if (luaStops('onStartCountdown')) {
		if (!startedCountdown) FunkinLua.countdownBlocked = true;
		e.cancel();
	}
}

function onCountdown(e) {
	if (FunkinLua.countdownBlocked) { e.cancel(); __blockNow(); return; }
	if (e.swagCounter == 0) fwd('onCountdownStarted');
	fwd('onCountdownTick', [e.swagCounter]);
}

function onSongEnd(e) {
	if (stopped(fwd('onEndSong'))) e.cancel();
}

function measureHit(m:Int) {
	__syncSectionGlobals(__camTargetAt(Conductor.songPosition + 1));
	fwd('onSectionHit');
}

function onNoteHit(e) {
	var cpu = e.note.strumLine != null && e.note.strumLine.cpu;
	var args:Array<Dynamic> = [__hitId++, e.direction, e.noteType, e.note.isSustainNote];
	if (cpu) {
		fwd('opponentNoteHit', args);
	} else {
		if (e.direction >= 0 && e.direction < 4) __hitNow[e.direction] = true;
		fwd('goodNoteHit', args);
	}
}

function onPlayerMiss(e) {
	if (e.ghostMiss) fwd('noteMissPress', [e.direction]); else {
		var sus = e.note != null ? e.note.isSustainNote : false;
		fwd('noteMiss', [__hitId++, e.direction, e.noteType, sus]);
	}
}

function onInputUpdate(e) {
	if (e.strumLine == null || e.strumLine.cpu) return;
	for (k in 0...e.justPressed.length) {
		if (e.justPressed[k]) {
			if (k < 4) __pressedNow[k] = true;
			fwd('onKeyPress', [k]);
		}
		if (e.justReleased[k]) fwd('onKeyRelease', [k]);
	}
}

////////// A port of cam Move to codeame using strumlines
function onCameraMove(e) {
	if (LuaHaxe.camProbe) return;
	if (e.strumLine != null && strumLines != null) {
		var camIdx:Int = strumLines.members.indexOf(e.strumLine);
		if (camIdx >= 0) __syncSectionGlobals(camIdx);
	}
	var focus = 'boyfriend';
	if (e.strumLine != null && e.strumLine.data != null) {
		switch (e.strumLine.data.position) {
			case 'dad': focus = 'dad';
			case 'girlfriend': focus = 'gf';
			default: focus = 'boyfriend';
		}
	}
	fwd('onMoveCamera', [focus]);
}

function onRatingUpdate(e) {
	if (stopped(fwd('onRecalculateRating'))) e.cancel();
}

//////////////This freeze all the variables, tweens and sounds
var __frozenTweens:Array<Dynamic> = [];
var __frozenTimers:Array<Dynamic> = [];
var __frozenSounds:Array<Dynamic> = [];
var __luaFrozen:Bool = false;

function __isGameAudio(s:Dynamic):Bool {
	if (s == null) return true;
	if (s == inst || s == vocals || s == FlxG.sound.music) return true;
	try {
		for (sl in strumLines.members)
			if (sl != null && sl.vocals == s) return true;
	} catch (e:Dynamic) {}
	return false;
}

function __videoPause() LuaVideos.pauseVideo();

function __videoResume() LuaVideos.resumeVideo();

function __freezeLua() {
	if (__luaFrozen) return;
	__luaFrozen = true;
	FunkinLua.gamePaused = true;

	__frozenTweens = [];

	try FlxTween.globalManager.forEach(function(t:Dynamic) {

		if (t != null && t.active && !t.finished) { t.active = false; __frozenTweens.push(t); }

	}) catch (e:Dynamic) {trace('[Lua] Could not create be freeze' + Std.string(e) + 'Tweens');}

	__frozenTimers = [];

	try FlxTimer.globalManager.forEach(function(t:Dynamic) {

		if (t != null && t.active && !t.finished) { t.active = false; __frozenTimers.push(t); }

	}) catch (e:Dynamic) {trace('[Lua] Could not create be freeze' + Std.string(e) + 'Timers');}

	__frozenSounds = [];
	try {
		for (snd in FlxG.sound.list.members) {
			if (snd == null || !snd.playing || __isGameAudio(snd)) snd.pause();
			__frozenSounds.push(snd);
		}
	} catch (e:Dynamic) {trace('[Lua] Could not create be freeze' + Std.string(e) + 'Sounds');}

	__videoPause();
}

function __unfreezeLua() {
	if (!__luaFrozen) return;
	__luaFrozen = false;
	FunkinLua.gamePaused = false;

	for (t in __frozenTweens) try t.active = true catch (e:Dynamic) {}
	for (t in __frozenTimers) try t.active = true catch (e:Dynamic) {}
	for (snd in __frozenSounds) try snd.resume() catch (e:Dynamic) {}
	__frozenTweens = [];
	__frozenTimers = [];
	__frozenSounds = [];

	__videoResume();
}

//////////Freeze functions
function onGamePause(e) {
	if (stopped(fwd('onPause'))) { e.cancel(); return; }
	__freezeLua();
}

function onSubstateOpen(e) {
	if (e.substate is DialogueCutscene) fwd('onNextDialogue', [0]);
	else if (e.substate is PauseSubState) {
		if (!__luaFrozen) { FunkinLua.gamePaused = true; __videoPause(); }
		if (LuaVideos.videoSprite != null) LuaVideos.videoSprite.visible = true;
	}
}

function onSubstateClose(e) {
	if (e.substate is PauseSubState) {
		fwd('onResume');
		if (__luaFrozen) __unfreezeLua();
		else { FunkinLua.gamePaused = false; __videoResume(); }
	}
	else if (e.substate is DialogueCutscene) fwd('onSkipDialogue', [0]);
}

////////////////////////////

function onGameOver(e) {
	if (stopped(fwd('onGameOver'))) { e.cancel(); return; }
	if (GameOverSubstate.script == null || GameOverSubstate.script == '')
		GameOverSubstate.script = 'data/gameovers/lua_gameover';
}

function onPostGameOver(e) {
	fwd('onGameOverStart');
	fwd('onPostGameOver', [evToObj(e)]);
}

function onPostStartCountdown() fwd('onPostStartCountdown');
function onStartSong() fwd('onStartSong');
function onStageDestroy() fwd('onStageDestroy');
function onFocus() fwd('onFocus');
function onFocusLost() fwd('onFocusLost');
function onVocalsResync() fwd('onVocalsResync');

function onPostCountdown(e) fwdEvent('onPostCountdown', e);
function onPostEvent(e) fwdEvent('onPostEvent', e);
function onPostNoteHit(e) fwdEvent('onPostNoteHit', e);
function onPostPlayerMiss(e) fwdEvent('onPostPlayerMiss', e);
function onPlayerHit(e) fwdEvent('onPlayerHit', e);
function onDadHit(e) fwdEvent('onDadHit', e);
function onNoteCreation(e) fwdEvent('onNoteCreation', e);
function onPostNoteCreation(e) fwdEvent('onPostNoteCreation', e);
function onSplashShown(e) fwdEvent('onSplashShown', e);
function onPreGenerateStrums(e) fwdEvent('onPreGenerateStrums', e);
function onPostGenerateStrums(e) fwdEvent('onPostGenerateStrums', e);

//////////////////////Destroy the luas
function destroy() {
	LuaEffects.reset();
	FunkinLua.countdownBlocked = false;
	LuaVideos.videoSprite = null;
	LuaVideos.videoName = null;
	FunkinLua.gamePaused = false;
	__luaFrozen = false;
	__frozenTweens = [];
	__frozenTimers = [];
	__frozenSounds = [];
	if (luaArray != null) {
		for (lua in luaArray.copy()) {
			lua.call('onDestroy', []);
			lua.stop();          
		}
		luaArray = null;
	}
	FunkinLua.getVariables().clear();
}
