package lua.helpers;

import funkin.game.PlayState;
import funkin.options.Options;
import haxe.ds.StringMap;
import lua.helpers.LuaShared;

using StringTools;

// Compatibilidad Psych para combo / rating / ClientPrefs (comboGroup, showCombo, comboOffset, scoreTxt...).
// (Parte de FunkinLua.hx dividida en modulos. Las funciones reciben `funk` = la instancia de FunkinLua.)
class LuaCombo {

	public static function comboAliasKey(funk:Dynamic, variable:String):String {
		if (variable == null) return null;
		var v:String = variable;
		for (pre in ['ClientPrefs.data.', 'ClientPrefs.', 'Options.', 'data.'])
			if (v.startsWith(pre)) { v = v.substr(pre.length); break; }
		return (v == 'showCombo' || v == 'showRating') ? v : null;
	}

	public static var prefsNames:StringMap<String> = [
		'downScroll' => 'downscroll',
		'ghostTapping' => 'ghostTapping',
		'flashing' => 'flashingMenu',
		'camZooms' => 'camZoomOnBeat',
		'shaders' => 'gameplayShaders',
		'lowQuality' => 'lowMemoryMode',
		'noteOffset' => 'songOffset',
		'framerate' => 'framerate',
		'antialiasing' => 'antialiasing',
		'splashesEnabled' => 'splashesEnabled',
		'autoPause' => 'autoPause',
		'naughtyness' => 'naughtyness'
	];

	public static var prefsDefaults:StringMap<Dynamic> = [
		'middleScroll' => false,
		'opponentStrums' => true,
		'hideHud' => false,
		'timeBarType' => 'Time Left',
		'scoreZoom' => true,
		'noReset' => false,
		'healthBarAlpha' => 1,
		'comboStacking' => true,
		'hitsoundVolume' => 0,
		'ratingOffset' => 0,
		'sickWindow' => 45,
		'goodWindow' => 90,
		'badWindow' => 135,
		'safeFrames' => 10,
		'pauseMusic' => 'Tea Time',
		'checkForUpdates' => false,
		'camZoomOnBeat' => true,
		'gameplaySettings' => []
	];

	public static function isPrefsClass(funk:Dynamic, classVar:String):Bool {
		return classVar != null && (classVar == 'ClientPrefs' || classVar == 'Options' || classVar.endsWith('.ClientPrefs') || classVar.endsWith('.Options'));
	}

	public static function prefsField(funk:Dynamic, variable:String):String {
		var v:String = variable;
		if (v.startsWith('data.')) v = v.substr(5);
		return LuaCombo.prefsNames.exists(v) ? LuaCombo.prefsNames.get(v) : v;
	}

	public static function comboOffsetIndex(funk:Dynamic, variable:String):Int {
		if (variable == null) return -1;
		var v:String = variable.startsWith('data.') ? variable.substr(5) : variable;
		if (v == 'comboOffset') return -2;
		if (!v.startsWith('comboOffset[') || !v.endsWith(']')) return -1;
		var n:Null<Int> = Std.parseInt(v.substr(12, v.length - 13));
		return (n != null && n >= 0 && n <= 3) ? n : -1;
	}

	public static function getComboOffset(funk:Dynamic, i:Int):Float {
		var g:Dynamic = PlayState.instance;
		if (g == null || g.comboGroup == null) return 0;
		return (i % 2 == 0) ? g.comboGroup.x - FlxG.width * 0.55 : (FlxG.height * 0.5 - 60) - g.comboGroup.y;
	}

	public static function setComboOffset(funk:Dynamic, i:Int, value:Dynamic):Void {
		var g:Dynamic = PlayState.instance;
		if (g == null || g.comboGroup == null) return;
		var f:Float = Std.parseFloat(Std.string(value));
		if (Math.isNaN(f)) return;
		if (i % 2 == 0) g.comboGroup.x = FlxG.width * 0.55 + f;
		else g.comboGroup.y = (FlxG.height * 0.5 - 60) - f;
	}

	public static function getComboOption(funk:Dynamic, key:String):Dynamic {
		var g:Dynamic = PlayState.instance;
		if (g == null) return true;
		return key == 'showCombo' ? g.minDigitDisplay >= 0 : g.defaultDisplayRating;
	}

	public static var origMinDigit:Null<Int> = null;

	public static function enforceComboCam(funk:Dynamic):Void {
		var g:Dynamic = PlayState.instance;
		if (funk.comboCam == null || g == null || g.comboGroup == null) return;
		try {
			var grp:Dynamic = g.comboGroup;
			var cam:flixel.FlxCamera = cast funk.comboCam;
			if (funk.comboCamArr == null || funk.comboCamArr[0] != cam) funk.comboCamArr = [cam];
			var inWorld:Bool = (funk.comboCam == g.camGame);

			// el recorrido recursivo de la escena es caro: solo se comprueba cada 30 frames
			if ((funk.comboSceneTick++ % 30) == 0) {
				var inScene:Bool = false;
				try inScene = (g.members.indexOf(grp) >= 0) || LuaShared.containsDeep(g, grp, 0) catch (e:Dynamic) {}
				if (!inScene) try g.add(grp) catch (e:Dynamic) {}
			}

			var gc:Dynamic = grp.cameras;
			if (gc == null || gc.length != 1 || gc[0] != cam) grp.cameras = funk.comboCamArr;
			try {
				if (!grp.visible) grp.visible = true;
				if (!grp.exists) grp.exists = true;
				if (!grp.active) grp.active = true;
			} catch (e:Dynamic) {}
			if (inWorld) try { if (grp.scrollFactor.x != 1 || grp.scrollFactor.y != 1) grp.scrollFactor.set(1, 1); } catch (e:Dynamic) {}

			var mem:Dynamic = Reflect.getProperty(grp, 'members');
			if (mem != null) {
				var arr:Array<Dynamic> = mem;
				for (m in arr) {
					if (m == null) continue;
					try {
						if (!m.exists && m.ID == 7777) m.ID = 0;
						var mc:Dynamic = m.cameras;
						if (mc == null || mc.length != 1 || mc[0] != cam) m.cameras = funk.comboCamArr;
						if (inWorld) {
							var sf:Dynamic = m.scrollFactor;
							if (sf.x != 1 || sf.y != 1) sf.set(1, 1);
						}
					} catch (e:Dynamic) {}
				}
			}
		} catch (e:Dynamic) {
			if (funk.comboDbgCount < 3) { funk.comboDbgCount++; LuaShared.luaTrace('[ComboGroup] enforceComboCam: ' + Std.string(e)); }
		}
	}

	public static function setComboOption(funk:Dynamic, key:String, value:Dynamic):Void {
		var g:Dynamic = PlayState.instance;
		if (g == null) return;
		var on:Bool = (value == true || value == 1 || value == 'true');
		if (key == 'showCombo') {
			if (LuaCombo.origMinDigit == null && g.minDigitDisplay >= 0) LuaCombo.origMinDigit = Std.int(g.minDigitDisplay);
			g.minDigitDisplay = on ? (LuaCombo.origMinDigit != null ? LuaCombo.origMinDigit : 0) : -1;
		}
		else g.defaultDisplayRating = on;
		LuaShared.setOnAll(key, on);
	}

	public static function ratingPercentValue(funk:Dynamic):Float {
		try {
			var f:Float = Std.parseFloat(Std.string(Reflect.getProperty(PlayState.instance, 'accuracy')));
			if (Math.isNaN(f) || f < 0) return 0;
			return f > 1 ? 1 : f;
		} catch (e:Dynamic) {}
		return 0;
	}

	public static function setPsychScoreTxtVisible(funk:Dynamic, v:Dynamic):Void {
		var g:Dynamic = PlayState.instance;
		if (g == null) return;
		for (n in ['scoreText', 'missesText', 'accuracyText']) {
			try {
				var o:Dynamic = Reflect.getProperty(g, n);
				if (o != null) Reflect.setProperty(o, 'visible', v);
			} catch (e:Dynamic) {}
		}
	}

	public static function comboPsychBaseX(funk:Dynamic):Float return FlxG.width * 0.35;

	public static function comboPsychBaseY(funk:Dynamic):Float return FlxG.height * 0.5;

	public static function refreshRating(funk:Dynamic):Void {
		try {
			PlayState.instance.updateRating();
		} catch (e:Dynamic) {}
	}
}
