package lua.helpers;

import funkin.game.PlayState;
import funkin.backend.assets.Paths;
import funkin.backend.shaders.CustomShader;
import openfl.utils.Assets;
import Utils.LuaUtils;
import lua.helpers.LuaShared;
import lua.helpers.LuaShaders;

using StringTools;

class LuaEffects {
	public static var active:Array<Dynamic> = [];
	public static var timed:Array<Dynamic> = [];
	static var hooked:Bool = false;

	public static function reset():Void {
		for (e in active) try e.cam.removeShader(e.shader) catch (x:Dynamic) {}
		active = [];
		timed = [];
	}

	static function tick():Void {
		var dt:Float = FlxG.elapsed;
		for (e in timed) {
			e.t += dt;
			try e.shader.hset(e.timeUniform, e.t) catch (x:Dynamic) {}
		}
	}

	public static function hook():Void {
		if (hooked) return;
		hooked = true;
		FlxG.signals.preUpdate.add(LuaEffects.tick);
	}

	public static function camOf(funk:Dynamic, name:String):Dynamic {
		return LuaShaders.safeCam(funk, name);
	}

	public static function add(funk:Dynamic, cam:String, kind:String, params:Array<Dynamic>, ?timeUniform:String = null, ?t0:Float = 0):Dynamic {
		if (!LuaShared.opt(['gameplayShaders', 'shaders'], true)) return null;
		if (!Assets.exists(Paths.fragShader(kind))) {
			LuaShared.luaTrace('add' + kind + 'Effect: falta shaders/' + kind + '.frag');
			return null;
		}
		var c:Dynamic = LuaEffects.camOf(funk, cam);
		var sh:Dynamic = null;
		try {
			sh = new CustomShader(kind);
			LuaEffects.setAll(sh, params);
			c.addShader(sh);
		} catch (e:Dynamic) {
			LuaShared.luaTrace('add' + kind + 'Effect: ' + Std.string(e));
			return null;
		}
		var entry:Dynamic = {cam: c, kind: kind, shader: sh, timeUniform: timeUniform, t: t0};
		active.push(entry);
		if (timeUniform != null) {
			try sh.hset(timeUniform, t0) catch (x:Dynamic) {}
			timed.push(entry);
			LuaEffects.hook();
		}
		return entry;
	}

	public static function setAll(sh:Dynamic, params:Array<Dynamic>):Void {
		for (p in params) {
			try sh.hset(p[0], p[1]) catch (e:Dynamic) LuaShared.luaTrace('shader uniform ' + p[0] + ': ' + Std.string(e));
		}
	}

	public static function find(funk:Dynamic, cam:String, kind:String):Dynamic {
		var c:Dynamic = LuaEffects.camOf(funk, cam);
		for (e in active) if (e.cam == c && e.kind == kind) return e;
		return null;
	}

	public static function pulse(set:Float->Void, from:Float, length:Float, ease:String):Void {
		set(from);
		if (length <= 0) { set(0.0); return; }
		var fn:Dynamic = null;
		try fn = LuaUtils.getTweenEaseByString(ease) catch (e:Dynamic) {}
		if (fn == null) fn = FlxEase.linear;
		FlxTween.num(from, 0.0, length, {ease: fn}, set);
	}

	public static function remove(entry:Dynamic):Void {
		try entry.cam.removeShader(entry.shader) catch (e:Dynamic) {}
		active.remove(entry);
		timed.remove(entry);
	}

	public static function hexColor(v:Dynamic, ?def:Int = 0xFFFFFFFF):Array<Float> {
		var n:Int = def;
		try {
			if (Std.isOfType(v, Int) || Std.isOfType(v, Float)) n = Std.int(v);
			else if (v != null && Std.string(v) != '') {
				var s:String = Std.string(v).replace('#', '').replace('0x', '');
				var p:Null<Int> = Std.parseInt('0x' + s);
				if (p != null) n = p;
			}
		} catch (e:Dynamic) {}
		return [((n >> 16) & 0xFF) / 255.0, ((n >> 8) & 0xFF) / 255.0, (n & 0xFF) / 255.0];
	}
}
