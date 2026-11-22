package lua.helpers;

import funkin.game.PlayState;
import funkin.backend.system.Logs;
import funkin.options.Options;
import haxe.ds.StringMap;

using StringTools;

class LuaShared {
	public static var all:Array<Dynamic> = [];
	public static var customFunctions:StringMap<Dynamic> = new StringMap<Dynamic>();
	public static var variables:StringMap<Dynamic> = new StringMap<Dynamic>();

	public static var Function_Stop:String = "##PSYCHLUA_FUNCTIONSTOP";
	public static var Function_Continue:String = "##PSYCHLUA_FUNCTIONCONTINUE";
	public static var Function_StopLua:String = "##PSYCHLUA_FUNCTIONSTOPLUA";
	public static var Function_StopHScript:String = "##PSYCHLUA_FUNCTIONSTOPHSCRIPT";
	public static var Function_StopAll:String = "##PSYCHLUA_FUNCTIONSTOPALL";

	public static function isLuaSupported(v:Dynamic):Bool {
		return v == null || Std.isOfType(v, Bool) || Std.isOfType(v, Int) || Std.isOfType(v, Float)
			|| Std.isOfType(v, String) || Std.isOfType(v, Array)
			|| (Reflect.isObject(v) && Type.getClass(v) == null && Type.getEnum(v) == null);
	}

	public static function containsDeep(container:Dynamic, target:Dynamic, depth:Int):Bool {
		if (container == null || depth > 6) return false;
		var m:Dynamic = null;
		try m = Reflect.getProperty(container, 'members') catch (e:Dynamic) {}
		if (m == null || !Std.isOfType(m, Array)) return false;
		var arr:Array<Dynamic> = m;
		if (arr.indexOf(target) >= 0) return true;
		for (c in arr) if (LuaShared.containsDeep(c, target, depth + 1)) return true;
		return false;
	}

	public static var hits:Int = 0;

	public static function setOnAll(variable:String, value:Dynamic, ?exclusions:Array<String> = null):Void {
		for (s in LuaShared.all.copy())
			if (!s.closed && (exclusions == null || !exclusions.contains(s.scriptName))) s.set(variable, value);
	}

	public static function callOnAll(func:String, ?args:Array<Dynamic> = null, ?ignoreStops:Bool = false, ?exclusions:Array<String> = null, ?excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaShared.Function_Continue;
		if (args == null) args = [];
		if (exclusions == null) exclusions = [];
		if (excludeValues == null) excludeValues = [LuaShared.Function_Continue];
		for (s in LuaShared.all.copy()) {
			if (s.closed || exclusions.contains(s.scriptName)) continue;
			var v:Dynamic = s.call(func, args);
			if ((v == LuaShared.Function_StopLua || v == LuaShared.Function_StopAll) && !excludeValues.contains(v) && !ignoreStops) {
				returnVal = v;
				break;
			}
			if (v != null && !excludeValues.contains(v)) returnVal = v;
		}
		return returnVal;
	}

	public static function withSelf(funk:Dynamic, list:Array<String>, ignoreSelf:Bool):Array<String> {
		var r:Array<String> = list == null ? [] : list;
		if (ignoreSelf && !r.contains(funk.scriptName)) r.push(funk.scriptName);
		return r;
	}

	public static function luaTrace(text:String, ?ignoreCheck:Bool = false, ?deprecated:Bool = false, ?color:FlxColor):Void {
		if (color == null) color = FlxColor.RED;
		var msg:String = '[Lua] ' + text;
		if (color == FlxColor.RED) Logs.error(msg);
		else if (color == FlxColor.YELLOW || color == FlxColor.ORANGE) Logs.warn(msg);
		else Logs.infos(msg);
		try {
			PlayState.instance.scripts.call('addTextToDebug', [text, color]);
		} catch (e:Dynamic) {}
	}

	public static function opt(names:Array<String>, def:Dynamic):Dynamic {
		for (n in names) {
			try {
				var v:Dynamic = Reflect.getProperty(Options, n);
				if (v != null) return v;
			} catch (e:Dynamic) {}
		}
		return def;
	}
}
