import lua.FunkinLua;
import lua.DebugLuaText;

import funkin.game.PlayState;
import funkin.menus.PauseSubState;
import funkin.game.cutscenes.DialogueCutscene;
import funkin.game.GameOverSubstate;
import funkin.backend.scripting.ModSubState;

using StringTools;

var LUA_ROOT:String = 'songs/';

public var luaArray:Array<FunkinLua> = FunkinLua.all;
public var camOther:FlxCamera;
private var luaDebugGroup:FlxTypedGroup<DebugLuaText>;

var __spawnId:Int = 0;
var __hitId:Int = 0;
var __pressedNow:Array<Bool> = [false, false, false, false];
var __hitNow:Array<Bool> = [false, false, false, false];

var __luaReady:Bool = false;      
var __deferredCountdown:Bool = false;
var __seenCb:Array<String> = [];

function stopped(r:Dynamic):Bool {
	if (r == null) return false;
	var v:String = Std.string(r);
	return v == FunkinLua.Function_Stop || v == FunkinLua.Function_StopAll;
}

// Llama a onStartCountdown en TODOS los Lua y dice si alguno devolvio Function_Stop.
// (callOnLuas se queda solo con el ultimo valor no nulo, y otro Lua podia pisar el Function_Stop.)
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

// El recorrido de notas activas de postUpdate (onSpawnNote) solo hace falta si algun Lua define esos callbacks.
var __wantsSpawn:Bool = true;
var __spawnScanLen:Int = -1;
function __rescanSpawn() {
	__spawnScanLen = luaArray.length;
	__wantsSpawn = false;
	for (script in luaArray)
		if (!script.closed && (script.hasFunction('onSpawnNote') || script.hasFunction('onSpawnNotePost'))) { __wantsSpawn = true; break; }
}

// Mantiene parada la cuenta atras y la cancion mientras un Lua pidio Function_Stop en onStartCountdown.
function __blockNow() {
	if (!__blockLogged) {
		__blockLogged = true;
		trace('[Lua] onStartCountdown devolvio Function_Stop: cuenta atras y cancion bloqueadas');
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
	__blockLogged = false;
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
	
	var seen:Array<String> = [];
	if (PlayState.SONG.events != null)
		for (event in PlayState.SONG.events)
			if (!seen.contains(event.name)) {
				seen.push(event.name);
				startLuasNamed('custom_events/' + event.name + '.lua');
			}
	loadLuaFolder('songs/' + PlayState.SONG.meta.name + '/scripts/');

	if (PlayState.SONG.events != null)
		for (ev in PlayState.SONG.events) {
			if (ev == null || ev.params == null) continue;
			var v1 = ev.params.length > 0 ? Std.string(ev.params[0]) : '';
			var v2 = ev.params.length > 1 ? Std.string(ev.params[1]) : '';
			callOnLuas('eventEarlyTrigger', [ev.name, v1, v2, ev.time]);
			callOnLuas('onEventPushed', [ev.name, v1, v2, ev.time]);
		}

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
	var path:String = Paths.getPath(LUA_ROOT + luaFile);
	if (!Assets.exists(path)) return false;
	return loadLua(path);
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
//CALLBACKS

function update(elapsed:Float) {
	if (FunkinLua.countdownBlocked) __blockNow();
	callOnLuas('onUpdate', [elapsed]);
}

function onEvent(e) {
	if (e == null || e.event == null) return;
	var p = e.event.params;
	fwd('onEvent', [e.event.name, (p != null && p.length > 0) ? Std.string(p[0]) : '', (p != null && p.length > 1) ? Std.string(p[1]) : '', e.event.time]);
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
			var a:Array<Dynamic> = [__spawnId++, n.strumID, n.noteType, n.isSustainNote, n.strumTime];
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
		// si el Lua ya arranco la cuenta atras dentro del propio callback (startDialogue/startCountdown), no se bloquea
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
	if (e.ghostMiss) {
		fwd('noteMissPress', [e.direction]);
	} else {
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

function onCameraMove(e) {
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

function onGamePause(e) {
	if (stopped(fwd('onPause'))) e.cancel();
}

function onSubstateOpen(e) {
	if (e.substate is DialogueCutscene) fwd('onNextDialogue', [0]);
}

function onSubstateClose(e) {
	if (e.substate is PauseSubState) fwd('onResume');
	else if (e.substate is DialogueCutscene) fwd('onSkipDialogue', [0]);
}

function onGameOver(e) {
	if (stopped(fwd('onGameOver'))) { e.cancel(); return; }
	// engancha data/gameovers/lua_gameover.hx para onGameOverConfirm
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

function destroy() {
	FunkinLua.countdownBlocked = false;
	if (luaArray != null) {
		for (lua in luaArray.copy()) {
			lua.call('onDestroy', []);
			lua.stop();          
		}
		luaArray = null;
	}
	FunkinLua.getVariables().clear();
}
