package lua.helpers;

import funkin.game.PlayState;
import funkin.backend.system.Conductor;
import funkin.backend.system.Logs;
import sys.io.File;
import lua.Lj;
import lua.helpers.LuaShared;

using StringTools;

////////////Convert the psych lua to codename
class LuaGlobals {

	public static var nilSafePath:String = null;

	public static function loadNilSafePrelude(funk:Dynamic, enabled:Bool) {
		if (!enabled || funk.L == null) return;
		try {
			if (LuaGlobals.nilSafePath == null) {
				var dir:String = Sys.getEnv('TEMP');
				if (dir == null || dir == '') dir = Sys.getEnv('TMPDIR');
				if (dir == null || dir == '') dir = '.';
				LuaGlobals.nilSafePath = dir.replace('\\', '/') + '/funkinlua_nilsafe.lua';
				var code:String =
					"local z=function(a) return a or 0 end\n" +
					"debug.setmetatable(nil,{" +
					"__add=function(a,b) return z(a)+z(b) end," +
					"__sub=function(a,b) return z(a)-z(b) end," +
					"__mul=function(a,b) return z(a)*z(b) end," +
					"__div=function(a,b) return z(a)/(b or 1) end," +
					"__mod=function(a,b) return z(a)%(b or 1) end," +
					"__pow=function(a,b) return z(a)^z(b) end," +
					"__unm=function(a) return 0 end," +
					"__len=function(a) return 0 end," +
					"__concat=function(a,b) return (a==nil and '' or tostring(a))..(b==nil and '' or tostring(b)) end})\n";
				File.saveContent(LuaGlobals.nilSafePath, code);
			}
			Lj.dofile(funk.L, LuaGlobals.nilSafePath);
		} catch (e:Dynamic) {
			Logs.warn('[Lua] Cannot load nilsafe: ' + Std.string(e));
		}
	}

	public static function hookNoteHits(funk:Dynamic) {
		var funk = funk; 
		var g:Dynamic = PlayState.instance;
		if (g == null || g.strumLines == null) return;
		var sls:Array<Dynamic> = g.strumLines.members;
		for (i in 0...sls.length) {
			var sl:Dynamic = sls[i];
			if (sl == null) continue;
			var opp:Bool = (i == 0);
			try {
				var side:Dynamic = Reflect.getProperty(sl, 'opponentSide');
				if (Std.isOfType(side, Bool)) opp = side;
			} catch (e:Dynamic) {}
			var sig:Dynamic = null;
			try sig = Reflect.getProperty(sl, 'onHit') catch (e:Dynamic) {}
			if (sig == null) continue;
			var cb:Dynamic->Void = function(ev:Dynamic) {
				if (funk.closed || funk.L == null) return;
				var note:Dynamic = null;
				try note = ev.note catch (e:Dynamic) {}
				var dir:Int = 0;
				try dir = Std.int(ev.direction) catch (e:Dynamic) {
					try dir = Std.int(note.strumID) catch (e2:Dynamic) {}
				}
				var nt:String = '';
				try { var t:Dynamic = ev.noteType; if (t != null) nt = Std.string(t); } catch (e:Dynamic) {}
				var sus:Bool = false;
				try sus = (note != null && note.isSustainNote == true) catch (e:Dynamic) {}
				var id:Int = 0;
				try id = Std.int(g.unspawnNotes.indexOf(note)) catch (e:Dynamic) {}
				funk.call(opp ? 'opponentNoteHit' : 'goodNoteHitReal', [id, dir, nt, sus]);
			};
			try {
				sig.add(cb);
				funk.hitHooks.push({sig: sig, cb: cb});
				if (opp) funk.hookedHits = true;
			} catch (e:Dynamic) {}
		}
	}

	///////Get the lua
	public static function gl(funk:Dynamic, name:String, f:Void->Dynamic, ?def:Dynamic = 0):Void {
		var v:Dynamic = null;
		try v = f() catch (e:Dynamic) {}
		if (v == null) v = def;
		try Lj.setGlobal(funk.L, name, v) catch (e:Dynamic) {}
	}

	/////////Sync the psych vars to codename equivalents
	public static function syncGlobals(funk:Dynamic):Void {
		var g:Dynamic = PlayState.instance;
		var L:Dynamic = funk.L;
		if (g == null || L == null) return;
		var c:Array<Dynamic> = funk.syncCache;
		if (c.length == 0) for (i in 0...14) c.push(null);
		var v:Dynamic = null;
		try {
			v = Conductor.curStep; if (v == null) v = 0; if (v != c[0]) { c[0] = v; Lj.setGlobal(L, 'curStep', v); }
			v = Conductor.curBeat; if (v == null) v = 0; if (v != c[1]) { c[1] = v; Lj.setGlobal(L, 'curBeat', v); }
			v = Conductor.curStepFloat; if (v == null) v = 0; if (v != c[2]) { c[2] = v; Lj.setGlobal(L, 'curDecStep', v); }
			v = Conductor.curBeatFloat; if (v == null) v = 0; if (v != c[3]) { c[3] = v; Lj.setGlobal(L, 'curDecBeat', v); }
			v = Conductor.curMeasure; if (v == null) v = 0; if (v != c[4]) { c[4] = v; Lj.setGlobal(L, 'curSection', v); }
			v = Conductor.bpm; if (v == null) v = 100; if (v != c[10]) { c[10] = v; Lj.setGlobal(L, 'bpm', v); }
			v = Conductor.bpm; if (v == null) v = 100; if (v != c[11]) { c[11] = v; Lj.setGlobal(L, 'curBpm', v); }
			v = Conductor.crochet; if (v == null) v = 600; if (v != c[12]) { c[12] = v; Lj.setGlobal(L, 'crochet', v); }
			v = Conductor.stepCrochet; if (v == null) v = 150; if (v != c[13]) { c[13] = v; Lj.setGlobal(L, 'stepCrochet', v); }
		} catch (e:Dynamic) {}
		try {
			v = g.inst.length; if (v == null) v = 0; if (v != c[5]) { c[5] = v; Lj.setGlobal(L, 'songLength', v); }
		} catch (e:Dynamic) { if (c[5] != 0) { c[5] = 0; Lj.setGlobal(L, 'songLength', 0); } }
		try {
			v = g.songScore; if (v == null) v = 0; if (v != c[6]) { c[6] = v; Lj.setGlobal(L, 'score', v); }
			v = g.misses; if (v == null) v = 0; if (v != c[7]) { c[7] = v; Lj.setGlobal(L, 'misses', v); }
			v = g.combo; if (v == null) v = 0; if (v != c[9]) { c[9] = v; Lj.setGlobal(L, 'combo', v); }
		} catch (e:Dynamic) {}
		v = LuaShared.hits; if (v != c[8]) { c[8] = v; Lj.setGlobal(L, 'hits', v); }
	}

	////////Set default vars
	public static function setGlobals(funk:Dynamic):Void {
		var funk = funk;
		var game:Dynamic = PlayState.instance;
		LuaGlobals.gl(funk, 'luaDebugMode', function() return false);
		LuaGlobals.gl(funk, 'luaDeprecatedWarnings', function() return true);
		LuaGlobals.gl(funk, 'modFolder', function() return funk.modFolder);
		LuaGlobals.gl(funk, 'currentModDirectory', function() return funk.modFolder);
		LuaGlobals.gl(funk, 'screenWidth', function() return FlxG.width);
		LuaGlobals.gl(funk, 'screenHeight', function() return FlxG.height);
		LuaGlobals.gl(funk, 'buildTarget', function() return Lj.osName());

		LuaGlobals.gl(funk, 'curBpm', function() return Conductor.bpm);
		LuaGlobals.gl(funk, 'bpm', function() return Conductor.bpm);
		LuaGlobals.gl(funk, 'crochet', function() return Conductor.crochet);
		LuaGlobals.gl(funk, 'stepCrochet', function() return Conductor.stepCrochet);
		LuaGlobals.gl(funk, 'scrollSpeed', function() return PlayState.SONG.scrollSpeed);
		LuaGlobals.gl(funk, 'songLength', function() return game.inst.length);
		LuaGlobals.gl(funk, 'songName', function() return PlayState.SONG.meta.name);
		LuaGlobals.gl(funk, 'songPath', function() return PlayState.SONG.meta.name.toLowerCase().replace(' ', '-'));
		LuaGlobals.gl(funk, 'curStage', function() return game.curStage);
		LuaGlobals.gl(funk, 'isStoryMode', function() return PlayState.isStoryMode);
		LuaGlobals.gl(funk, 'difficultyName', function() return PlayState.difficulty);
		LuaGlobals.gl(funk, 'difficultyPath', function() return PlayState.difficulty.toLowerCase());
		LuaGlobals.gl(funk, 'hasVocals', function() return PlayState.SONG.meta.needsVoices != false);
		LuaGlobals.gl(funk, 'startedCountdown', function() return false);

		LuaGlobals.gl(funk, 'curSection', function() return 0);
		LuaGlobals.gl(funk, 'curDecBeat', function() return 0);
		LuaGlobals.gl(funk, 'curDecStep', function() return 0);
		LuaGlobals.gl(funk, 'score', function() return game.songScore);
		LuaGlobals.gl(funk, 'misses', function() return game.misses);
		LuaGlobals.gl(funk, 'hits', function() return LuaShared.hits);
		LuaGlobals.gl(funk, 'combo', function() return game.combo);
		LuaGlobals.gl(funk, 'rating', function() return 0);
		LuaGlobals.gl(funk, 'ratingName', function() return '?');
		LuaGlobals.gl(funk, 'ratingFC', function() return '');
		LuaGlobals.gl(funk, 'inGameOver', function() return false);
		LuaGlobals.gl(funk, 'mustHitSection', function() return false);
		LuaGlobals.gl(funk, 'altAnim', function() return false);
		LuaGlobals.gl(funk, 'gfSection', function() return false);
		LuaGlobals.gl(funk, 'healthGainMult', function() return 1);
		LuaGlobals.gl(funk, 'healthLossMult', function() return 1);
		LuaGlobals.gl(funk, 'playbackRate', function() return 1);
		LuaGlobals.gl(funk, 'botPlay', function() {
			var bp:Dynamic = false;
			try bp = game.strumLines.members[1].cpu catch (e:Dynamic) {}
			return bp == true;
		});
		LuaGlobals.gl(funk, 'practice', function() return false);

		LuaGlobals.gl(funk, 'downscroll', function() return LuaShared.opt(['downscroll'], false));
		LuaGlobals.gl(funk, 'middlescroll', function() return LuaShared.opt(['middleScroll', 'middlescroll'], false));
		LuaGlobals.gl(funk, 'framerate', function() return LuaShared.opt(['framerate'], 60));
		LuaGlobals.gl(funk, 'ghostTapping', function() return LuaShared.opt(['ghostTapping'], false));
		LuaGlobals.gl(funk, 'flashingLights', function() return LuaShared.opt(['flashingMenu', 'flashingLights'], true));
		LuaGlobals.gl(funk, 'cameraZoomOnBeat', function() return LuaShared.opt(['camZoomOnBeat', 'camZooms'], true));
		LuaGlobals.gl(funk, 'lowQuality', function() return LuaShared.opt(['lowMemoryMode', 'lowQuality'], false));
		LuaGlobals.gl(funk, 'shadersEnabled', function() return LuaShared.opt(['gameplayShaders', 'shaders'], true));
		LuaGlobals.gl(funk, 'noteOffset', function() return LuaShared.opt(['songOffset', 'noteOffset'], 0));
		LuaGlobals.gl(funk, 'showCombo', function() return game == null ? true : game.minDigitDisplay >= 0);
		LuaGlobals.gl(funk, 'showRating', function() return game == null ? true : game.defaultDisplayRating);
		LuaGlobals.gl(funk, 'hideHud', function() return false);
		LuaGlobals.gl(funk, 'healthBarAlpha', function() return 1);

		for (i in 0...4) {
			LuaGlobals.gl(funk, 'defaultPlayerStrumX' + i, function() return 0);
			LuaGlobals.gl(funk, 'defaultPlayerStrumY' + i, function() return 0);
			LuaGlobals.gl(funk, 'defaultOpponentStrumX' + i, function() return 0);
			LuaGlobals.gl(funk, 'defaultOpponentStrumY' + i, function() return 0);
		}
	}

	/////////Basically set the same
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
					LuaShared.setOnAll('default' + pre + 'StrumX' + i, strums[i].x);
					LuaShared.setOnAll('default' + pre + 'StrumY' + i, strums[i].y);
				}
			}
		} catch (e:Dynamic) {}
		try {
			if (game.boyfriend != null) { LuaShared.setOnAll('defaultBoyfriendX', game.boyfriend.x); LuaShared.setOnAll('defaultBoyfriendY', game.boyfriend.y); LuaShared.setOnAll('boyfriendName', game.boyfriend.curCharacter); }
			if (game.dad != null) { LuaShared.setOnAll('defaultOpponentX', game.dad.x); LuaShared.setOnAll('defaultOpponentY', game.dad.y); LuaShared.setOnAll('dadName', game.dad.curCharacter); }
			if (game.gf != null) { LuaShared.setOnAll('defaultGirlfriendX', game.gf.x); LuaShared.setOnAll('defaultGirlfriendY', game.gf.y); LuaShared.setOnAll('gfName', game.gf.curCharacter); }
		} catch (e:Dynamic) {}
	}
}
