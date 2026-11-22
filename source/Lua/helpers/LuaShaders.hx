package lua.helpers;

import funkin.game.PlayState;
import funkin.backend.assets.Paths;
import funkin.backend.shaders.CustomShader;
import funkin.backend.shaders.FunkinShader;
import openfl.filters.ShaderFilter;
import openfl.utils.Assets;
import Utils.LuaUtils;
import lua.helpers.LuaShared;
import lua.helpers.LuaProps;

using StringTools;


class LuaShaders {

	public static function initLuaShader(funk:Dynamic, name:String):Bool {
		if (funk.shaderNames.exists(name)) return true;
		if (!Assets.exists(Paths.fragShader(name)) && !Assets.exists(Paths.vertShader(name))) {
			LuaShared.luaTrace('initLuaShader: Shader ' + name + ' is missing!');
			return false;
		}
		funk.shaderNames.set(name, true);
		return true;
	}

	public static function getShaderTarget(funk:Dynamic, obj:String):Dynamic {
		var o:Dynamic = LuaProps.getLuaObject(funk, obj);
		if (o != null) return o;
		var split:Array<String> = obj.split('.');
		var target:Dynamic = LuaProps.resolveObject(funk, split[0]);
		if (split.length > 1) target = LuaProps.getVarInArray(funk, LuaUtils.getPropertyLoop(split), split[split.length - 1]);
		return target;
	}

	public static function getShader(funk:Dynamic, obj:String, ?fn:String = 'getShader'):Dynamic {
		var sh:Dynamic = funk.objShaders.get(obj);        
		if (sh == null) {
			var target:Dynamic = LuaShaders.getShaderTarget(funk, obj);
			if (target == null) { LuaShared.luaTrace('$fn: Object $obj not found'); return null; }
			try sh = Reflect.getProperty(target, 'shader') catch (e:Dynamic) {}
		}
		if (sh == null) {
			LuaShared.luaTrace('$fn: Object $obj has no shader');
			return null;
		}
		return sh;
	}

	public static function removeShaderFrom(funk:Dynamic, obj:String, target:Dynamic):Void {
		var old:Dynamic = funk.objShaders.get(obj);
		if (old != null && Std.isOfType(target, FlxCamera)) try target.removeShader(old) catch (e:Dynamic) {}
	}

	public static function shim_initLuaShader(funk:Dynamic, name:String, ?glslVersion:Dynamic = null):Bool {
		if (!LuaShared.opt(['gameplayShaders', 'shaders'], true)) return false;
		return LuaShaders.initLuaShader(funk, name);
	}

	public static function shim_createRuntimeShader(funk:Dynamic, name:String, ?glslVersion:Dynamic = null):Dynamic {
		if (!LuaShared.opt(['gameplayShaders', 'shaders'], true)) return null;
		LuaShaders.initLuaShader(funk, name);
		try {
			return new CustomShader(name);
		} catch (e:Dynamic) {
			LuaShared.luaTrace('createRuntimeShader: ' + Std.string(e));
		}
		return null;
	}

	public static function shim_getLuaObject(funk:Dynamic, tag:String, ?text:Bool = true):Dynamic {
		var o:Dynamic = LuaProps.getLuaObject(funk, tag);
		if (o == null) {
			try o = LuaShared.variables.get(tag) catch (e:Dynamic) {}
		}
		return o;
	}

	public static function shim_shaderOf(funk:Dynamic, tag:String):Dynamic {
		var sh:Dynamic = funk.objShaders.get(tag);
		if (sh != null) return sh;
		var o:Dynamic = LuaShaders.shim_getLuaObject(funk, tag);
		if (o == null) {
			LuaShared.luaTrace('getLuaObject("' + tag + '").shader: the object doesnt exist', false, false, FlxColor.YELLOW);
			return null;
		}
		try sh = Reflect.getProperty(o, 'shader') catch (e:Dynamic) {}
		if (sh == null) LuaShared.luaTrace('getLuaObject("' + tag + '").shader: the object has no shader', false, false, FlxColor.YELLOW);
		return sh;
	}

	public static function shim_setShaderOf(funk:Dynamic, tag:String, shader:Dynamic):Dynamic {
		if (shader == null) {
			LuaShared.luaTrace('getLuaObject("' + tag + '").shader = null (the shader couldnt be created, does it exist?)', false, false, FlxColor.YELLOW);
			return null;
		}
		var o:Dynamic = LuaShaders.shim_getLuaObject(funk, tag);
		if (o != null) {
			try Reflect.setProperty(o, 'shader', shader) catch (e:Dynamic) {}
		}
		funk.objShaders.set(tag, shader);
		return shader;
	}

	public static function shim_camOther(funk:Dynamic):Dynamic {
		var c:Dynamic = null;
		try c = LuaShared.variables.get('camOther') catch (e:Dynamic) {}
		if (c == null) {
			c = FlxG.cameras.list[FlxG.cameras.list.length - 1];
			try LuaShared.variables.set('camOther', c) catch (e:Dynamic) {}
		}
		return c;
	}

	public static function shim_filter(funk:Dynamic, shader:Dynamic):Dynamic {
		if (shader == null) {
			LuaShared.luaTrace('ShaderFilter: the shader couldnt be created using a null one', false, false, FlxColor.YELLOW);
			shader = new FunkinShader(null, null);
		}
		if (Std.isOfType(shader, FlxSprite)) {
			var fromSpr:Dynamic = null;
			try fromSpr = Reflect.getProperty(shader, 'shader') catch (e:Dynamic) {}
			shader = fromSpr != null ? fromSpr : new FunkinShader(null, null);
		}
		return new ShaderFilter(cast shader);
	}

	public static function safeCam(funk:Dynamic, name:String):FlxCamera {
		var n:String = name == null ? '' : name.toLowerCase();
		var c:Dynamic = null;
		if (n == 'other' || n == 'camother') {
			c = LuaShaders.shim_camOther(funk);
		} else {
			try c = LuaUtils.cameraFromString(name) catch (e:Dynamic) {}
			if (c == null) {
				var g:Dynamic = PlayState.instance;
				if (g != null) c = (n == 'hud' || n == 'camhud') ? g.camHUD : g.camGame;
			}
		}
		if (c == null) c = FlxG.camera;
		return c;
	}

	public static function shaderGet(funk:Dynamic, obj:String, prop:String, fn:String):Dynamic {
		var s:Dynamic = LuaShaders.getShader(funk, obj, fn);
		if (s == null) return null;
		try {
			return s.hget(prop);
		} catch (e:Dynamic) {
			LuaShared.luaTrace(fn + ': ' + Std.string(e));
		}
		return null;
	}

	public static function shaderSet(funk:Dynamic, obj:String, prop:String, value:Dynamic, fn:String):Bool {
		var s:Dynamic = LuaShaders.getShader(funk, obj, fn);
		if (s == null) return false;
		try {
			s.hset(prop, value);
			return true;
		} catch (e:Dynamic) {
			try {
				var p:Dynamic = Reflect.field(s.data, prop);
				if (p != null) {
					p.value = Std.isOfType(value, Array) ? value : [value];
					return true;
				}
			} catch (e2:Dynamic) {}
			LuaShared.luaTrace(fn + ': ' + Std.string(e));
		}
		return false;
	}
}
