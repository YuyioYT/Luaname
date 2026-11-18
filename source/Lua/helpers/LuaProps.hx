package lua.helpers;

import funkin.game.PlayState;
import funkin.game.Character;
import funkin.backend.assets.Paths;
import funkin.backend.system.Conductor;
import funkin.options.Options;
import haxe.ds.StringMap;
import Utils.LuaUtils;
import lua.helpers.LuaShared;
import lua.helpers.LuaCombo;

using StringTools;

////////More conversions
class LuaProps {

	public static function getLuaObject(funk:Dynamic, tag:String):Dynamic return LuaProps.resolveObject(funk, tag);

	public static function resolveObject(funk:Dynamic, name:String):Dynamic {
		if (name == null) return null;
		var o:Dynamic = LuaProps.lookupObject(funk, name);
		if (o != null) return o;
		var game:Dynamic = PlayState.instance;
		if (game != null) {
			var key:String = LuaProps.propAliases.exists(name) ? LuaProps.propAliases.get(name) : name;
			try {
				var p:Dynamic = Reflect.getProperty(game, key);
				if (p != null && Std.isOfType(p, FlxBasic)) return p;
			} catch (e:Dynamic) {}
			if (name.indexOf('.') >= 0 || name.indexOf('[') >= 0) {
				try {
					var q:Dynamic = LuaProps.getProperty(funk, name);
					if (q != null && !Std.isOfType(q, String) && !Std.isOfType(q, Float) && !Std.isOfType(q, Bool)) return q;
				} catch (e:Dynamic) {}
			}
		}
		try { o = LuaUtils.getObjectDirectly(name); } catch (e:Dynamic) {}
		return o;
	}

	public static function borderStyleOf(funk:Dynamic, name:String):Dynamic {
		try {
			var e:Dynamic = Type.resolveEnum('flixel.text.FlxTextBorderStyle');
			if (e != null) return Type.createEnum(e, name);
		} catch (e:Dynamic) {}
		return null;
	}

	public static function lookupObject(funk:Dynamic, name:String):Dynamic {
		if (name == null) return null;
		var o:Dynamic = LuaShared.variables.get(name);
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

	public static function isMap(funk:Dynamic, o:Dynamic):Bool return o != null && Reflect.isFunction(Reflect.field(o, 'exists')) && Reflect.isFunction(Reflect.field(o, 'keys'));

	public static function addAnimByIndices(funk:Dynamic, obj:String, name:String, prefix:String, indices:Dynamic, framerate:Float, loop:Bool):Bool {
		var o:Dynamic = LuaProps.resolveObject(funk, obj);
		if (o == null || o.animation == null) {
			LuaShared.luaTrace('addAnimationByIndices: Object ' + obj + ' doesn\'t exist!', false, false, FlxColor.RED);
			return false;
		}
		var arr:Array<Int> = [];
		if (Std.isOfType(indices, String)) {
			var parts:Array<String> = Std.string(indices).split(',');
			for (ps in parts) {
				var pn:Null<Int> = Std.parseInt(StringTools.trim(ps));
				if (pn != null) arr.push(pn);
			}
		} else if (Std.isOfType(indices, Array)) {
			var src:Array<Dynamic> = indices;
			for (v in src) arr.push(Std.int(Std.parseFloat(Std.string(v))));
		}
		if (arr.length == 0) {
			LuaShared.luaTrace('addAnimationByIndices: no valid indices for animation ' + name, false, false, FlxColor.YELLOW);
			return false;
		}
		if (prefix == null) o.animation.add(name, arr, framerate, loop);
		else o.animation.addByIndices(name, prefix, arr, '', framerate, loop);
		if (o.animation.curAnim == null) o.animation.play(name, true);
		return true;
	}

	public static function getVarInArray(funk:Dynamic, instance:Dynamic, variable:String, ?allowMaps:Bool = false):Dynamic {
		if (instance == null) return null;
		var parts:Array<String> = variable.split('[');
		var blah:Dynamic = (allowMaps && LuaProps.isMap(funk, instance)) ? instance.get(parts[0]) : Reflect.getProperty(instance, parts[0]);
		for (i in 1...parts.length) {
			if (blah == null) return null;
			var key:Dynamic = parts[i].substr(0, parts[i].length - 1);
			var n:Null<Int> = Std.parseInt(key);
			if (n != null) key = n;
			blah = LuaProps.isMap(funk, blah) ? blah.get(key) : blah[key];
		}
		return blah;
	}

	public static function setVarInArray(funk:Dynamic, instance:Dynamic, variable:String, value:Dynamic, ?allowMaps:Bool = false):Dynamic {
		if (instance == null) return null;
		var parts:Array<String> = variable.split('[');
		if (parts.length == 1) {
			if (allowMaps && LuaProps.isMap(funk, instance)) instance.set(variable, value);
			else {
				try Reflect.setProperty(instance, variable, value) catch (e:Dynamic) {
					if (variable != 'allowDebugKeys')
						LuaShared.luaTrace('setProperty: field ' + variable + ' does not exist in Codename (ignored)', false, false, FlxColor.YELLOW);
				}
			}
			return value;
		}
		var blah:Dynamic = (allowMaps && LuaProps.isMap(funk, instance)) ? instance.get(parts[0]) : Reflect.getProperty(instance, parts[0]);
		for (i in 1...parts.length) {
			if (blah == null) return null;
			var key:Dynamic = parts[i].substr(0, parts[i].length - 1);
			var n:Null<Int> = Std.parseInt(key);
			if (n != null) key = n;
			if (i == parts.length - 1) {
				if (LuaProps.isMap(funk, blah)) blah.set(key, value); else blah[key] = value;
				return value;
			}
			blah = LuaProps.isMap(funk, blah) ? blah.get(key) : blah[key];
		}
		return value;
	}

	public static function getPath(funk:Dynamic, root:Dynamic, path:String, ?allowMaps:Bool = false):Dynamic {
		var obj:Dynamic = root;
		for (part in path.split('.')) {
			if (obj == null) return null;
			obj = LuaProps.getVarInArray(funk, obj, part, allowMaps);
		}
		return obj;
	}

	public static function setPath(funk:Dynamic, root:Dynamic, path:String, value:Dynamic, ?allowMaps:Bool = false):Void {
		var split:Array<String> = path.split('.');
		var obj:Dynamic = root;
		for (i in 0...split.length - 1) {
			if (obj == null) return;
			obj = LuaProps.getVarInArray(funk, obj, split[i], allowMaps);
		}
		LuaProps.setVarInArray(funk, obj, split[split.length - 1], value, allowMaps);
	}

	public static function resolveRoot(funk:Dynamic, variable:String):Array<Dynamic> {
		var firstDot:Int = variable.indexOf('.');
		var head:String = firstDot < 0 ? variable : variable.substr(0, firstDot);
		if (LuaProps.propAliases.exists(head)) variable = LuaProps.propAliases.get(head) + (firstDot < 0 ? '' : variable.substr(firstDot));
		var split:Array<String> = variable.split('.');
		if (split.length > 1 && split[0].indexOf('[') < 0) {
			var tagged:Dynamic = LuaProps.lookupObject(funk, split[0]);
			if (tagged != null) return [tagged, split.slice(1).join('.')];
		}
		if (variable.indexOf('.') < 0 && variable.indexOf('[') < 0) {
			var single:Dynamic = LuaProps.lookupObject(funk, variable);
			if (single != null) return [{ _o: single }, '_o'];
		}
		return [LuaUtils.getTargetInstance(), variable];
	}

	public static function psychMid(funk:Dynamic, obj:Dynamic, wantX:Bool):Float {
		try {
			var g:Dynamic = PlayState.instance;
			if (g != null && Std.isOfType(obj, Character)) {
				var p:Dynamic = obj.getCameraPosition();
				if (p != null) {
					var dx:Float = 0;
					var dy:Float = 0;
					if (obj == g.boyfriend) { dx = 100; dy = 100; }
					else if (obj == g.dad) { dx = -150; dy = 100; }
					return wantX ? p.x + dx : p.y + dy;
				}
			}
		} catch (e:Dynamic) {}
		var mp:Dynamic = obj.getMidpoint();
		return wantX ? mp.x : mp.y;
	}

	public static function getProperty(funk:Dynamic, variable:String, ?allowMaps:Bool = false):Dynamic {
		if (variable == null) return null;
		if (variable == 'ratingPercent') return LuaCombo.ratingPercentValue(funk);
		var ck:String = LuaCombo.comboAliasKey(funk, variable);
		if (ck != null) return LuaCombo.getComboOption(funk, ck);
		if ((variable == 'comboGroup.x' || variable == 'comboGroup.y') && PlayState.instance != null && PlayState.instance.comboGroup != null)
			return variable == 'comboGroup.x' ? PlayState.instance.comboGroup.x - LuaCombo.comboPsychBaseX(funk) : PlayState.instance.comboGroup.y - LuaCombo.comboPsychBaseY(funk);
		var r:Array<Dynamic> = LuaProps.resolveRoot(funk, variable);
		var res:Dynamic = LuaProps.getPath(funk, r[0], r[1], allowMaps);
		if (res == null) {
			// propiedades de Psych con nombre distinto en Codename
			var g:Dynamic = PlayState.instance;
			if (g != null) {
				try {
					switch (variable) {
						case 'health': return g.health;
						case 'songPosition': return Conductor.songPosition;
						case 'curBeat': return Conductor.curBeat;
						case 'curStep': return Conductor.curStep;
						case 'cameraSpeed': return 1;
						case 'defaultCamZoom': return g.defaultCamZoom;
						case 'camGame.zoom': return g.camGame.zoom;
						case 'camHUD.zoom': return g.camHUD.zoom;
					}
				} catch (e:Dynamic) {}
			}
			var fb:Dynamic = LuaProps.numericFallback(funk, variable);
			if (fb != null) return fb;
		}
		return res;
	}

	public static function setProperty(funk:Dynamic, variable:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false):Void {
		if (variable == null) return;
		if (variable == 'scoreTxt.visible') { LuaCombo.setPsychScoreTxtVisible(funk, value); return; }
		var ck:String = LuaCombo.comboAliasKey(funk, variable);
		if (ck != null) { LuaCombo.setComboOption(funk, ck, value); return; }
		if ((variable == 'comboGroup.x' || variable == 'comboGroup.y') && PlayState.instance != null && PlayState.instance.comboGroup != null) {
			var fv:Float = Std.parseFloat(Std.string(value));
			if (variable == 'comboGroup.x') PlayState.instance.comboGroup.x = fv + LuaCombo.comboPsychBaseX(funk);
			else PlayState.instance.comboGroup.y = fv + LuaCombo.comboPsychBaseY(funk);
			return;
		}
		var r:Array<Dynamic> = LuaProps.resolveRoot(funk, variable);
		LuaProps.setPath(funk, r[0], r[1], LuaProps.parseInstance(funk, value, allowInstances), allowMaps);
	}

	public static function parseInstance(funk:Dynamic, value:Dynamic, allowInstances:Bool):Dynamic {
		if (allowInstances && Std.isOfType(value, String)) {
			var str:String = value;
			if (str.charAt(0) == '@') {
				var o:Dynamic = LuaShared.variables.get(str.substr(1));
				if (o != null) return o;
			}
		}
		return value;
	}

	public static function strumsOf(funk:Dynamic, name:String):Array<Dynamic> {
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

	public static function groupMember(funk:Dynamic, group:String, index:Int):Dynamic {
		var sg:Array<Dynamic> = LuaProps.strumsOf(funk, group);
		if (sg != null) return index >= 0 && index < sg.length ? sg[index] : null;
		var grp:Dynamic = LuaShared.variables.get(group);
		if (grp == null) grp = LuaProps.getProperty(funk, group);
		if (grp == null) return null;
		if (Std.isOfType(grp, Array)) return grp[index];
		var members:Dynamic = Reflect.getProperty(grp, 'members');
		return members != null ? members[index] : null;
	}

	public static function getChar(funk:Dynamic, type:String):Dynamic {
		var g:Dynamic = PlayState.instance;
		switch (type.toLowerCase()) {
			case 'dad' | 'opponent': return g.dad;
			case 'gf' | 'girlfriend': return g.gf;
			default: return g.boyfriend;
		}
	}

	public static function getStrum(funk:Dynamic, note:Int):Dynamic {
		var flat:Array<Dynamic> = [];
		for (sl in PlayState.instance.strumLines.members)
			for (s in sl.members) flat.push(s);
		return flat.length == 0 ? null : flat[note % flat.length];
	}

	public static function getSound(funk:Dynamic, tag:String):Dynamic {
		if (tag == null || tag.length < 1) return FlxG.sound.music;
		return LuaShared.variables.get(LuaUtils.formatVariable('sound_$tag'));
	}

	public static function getText(funk:Dynamic, tag:String):FlxText {
		var t:Dynamic = LuaShared.variables.get(tag);
		return (t != null && Std.isOfType(t, FlxText)) ? t : null;
	}

	public static function setOutline(funk:Dynamic, t:FlxText, size:Float, color:Int):Void {
		var bs:Dynamic = LuaProps.borderStyleOf(funk, 'OUTLINE');
		if (bs != null) t.borderStyle = bs;
		t.borderSize = size;
		t.borderColor = color;
	}

	public static function numericFallback(funk:Dynamic, variable:String):Dynamic {
		var parts:Array<String> = variable.split('.');
		var last:String = parts[parts.length - 1];
		var v:Dynamic = null;
		switch (last) {
			case 'x' | 'y' | 'angle' | 'zoom' | 'width' | 'height' | 'velocity' | 'health' | 'songPosition' | 'curBeat' | 'curStep' | 'camZoomingStrength' | 'camZoomingInterval' | 'combo' | 'misses' | 'songScore' | 'frame' | 'offset':
				v = 0;
			case 'alpha':
				v = 0;
			case 'defaultCamZoom' | 'cameraSpeed' | 'playbackRate' | 'songSpeed' | 'camZoomingMult':
				v = 1;
		}
		if (v != null && !funk.warnedNil.exists(variable)) {
			funk.warnedNil.set(variable, true);
			LuaShared.luaTrace('getProperty: "' + variable + '" is nil in Codename (returning ' + v + ')', false, false, FlxColor.YELLOW);
		}
		return v;
	}

	public static var classAliases:StringMap<String> = [
		'PlayState' => 'funkin.game.PlayState',
		'Conductor' => 'funkin.backend.system.Conductor',
		'Paths' => 'funkin.backend.assets.Paths',
		'CoolUtil' => 'funkin.backend.utils.CoolUtil',
		'Character' => 'funkin.game.Character',
		'Note' => 'funkin.game.Note',
		'StrumNote' => 'funkin.game.Strum',
		'ClientPrefs' => 'funkin.options.Options',
		'backend.ClientPrefs' => 'funkin.options.Options',
		'states.PlayState' => 'funkin.game.PlayState',
		'backend.Conductor' => 'funkin.backend.system.Conductor',
		'backend.CoolUtil' => 'funkin.backend.utils.CoolUtil',
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

	public static var propAliases:StringMap<String> = [
		'opponentStrums' => 'cpuStrums',
		'scoreTxt' => 'scoreText',
		'boyfriendGroup' => 'boyfriend',
		'dadGroup' => 'dad',
		'gfGroup' => 'gf'
	];

	public static function resolveClassByName(funk:Dynamic, name:String):Dynamic {
		if (name == null) return null;
		var c:Dynamic = Type.resolveClass(name);
		if (c == null && LuaProps.classAliases.exists(name)) c = Type.resolveClass(LuaProps.classAliases.get(name));
		return c;
	}

	public static function lowestCharacterIndex(funk:Dynamic, instance:Dynamic):Int {
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

	public static function convertEventParam(funk:Dynamic, v:Dynamic):Dynamic {
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
}
