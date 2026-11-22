package lua.helpers;

import funkin.game.PlayState;
import funkin.backend.scripting.Script;
import openfl.filters.ShaderFilter;
import lua.Lj;
import lua.helpers.LuaShared;

using StringTools;

//////////RUN HAXE CODE AND SHADERS
class LuaHaxe {

	public static var reShimSet:EReg = new EReg("parentLua\\.shim_getLuaObject\\(([^()]*)\\)\\.shader\\s*=\\s*([^;]+);", "g");
	public static var reShimShader:EReg = new EReg("parentLua\\.shim_getLuaObject\\(([^()]*)\\)\\.shader([^A-Za-z0-9_]|$)", "g");
	public static var reMoveCam:EReg = new EReg("(?:PlayState\\.instance|game)\\.moveCamera\\(([^()]+)\\)", "g");
	public static var reFastCam:EReg = new EReg("^\\s*(?:PlayState\\.instance|game)\\.moveCamera\\(\\s*(true|false|'dad'|'gf'|'boyfriend'|\"dad\"|\"gf\"|\"boyfriend\")\\s*\\)\\s*;?\\s*$", "");
	public static var camProbe:Bool = false;
	public static var reFn:EReg = new EReg("function\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(([^)]*)\\)\\s*\\{", "g");
	public static var reIdent:EReg = new EReg("^[A-Za-z_][A-Za-z0-9_]*$", "");

	public static function shimPsychHaxe(funk:Dynamic, code:String):String {
		for (pre in ['PlayState.instance', 'game']) {
			for (fn in ['initLuaShader', 'createRuntimeShader', 'getLuaObject'])
				code = code.split(pre + '.' + fn + '(').join('parentLua.shim_' + fn + '(');
			code = code.split(pre + '.camOther').join('parentLua.shim_camOther()');
		}
		code = LuaHaxe.reMoveCam.replace(code, "(function(__d) { var __g = PlayState.instance; var __o = __g.curCameraTarget; __g.curCameraTarget = (__d == true || __d == 'dad') ? 0 : ((__d == 'gf') ? 2 : 1); lua.helpers.LuaHaxe.camProbe = true; __g.moveCamera(); lua.helpers.LuaHaxe.camProbe = false; __g.curCameraTarget = __o; })($1)");
		code = LuaHaxe.reShimSet.replace(code, "parentLua.shim_setShaderOf($1, $2);");
		code = LuaHaxe.reShimShader.replace(code, "parentLua.shim_shaderOf($1)$2");
		code = code.split('new ShaderFilter(').join('parentLua.shim_filter(');
		return code;
	}

	public static function presetHScript(funk:Dynamic, s:Dynamic, ?varsToBring:Dynamic = null):Void {
		var s = s;
		var self:Dynamic = funk;
		s.set('parentLua', self);
		s.set('game', PlayState.instance);
		s.set('buildTarget', Lj.osName());

		s.set('Function_Stop', LuaShared.Function_Stop);
		s.set('Function_Continue', LuaShared.Function_Continue);
		s.set('Function_StopLua', LuaShared.Function_StopLua);
		s.set('Function_StopHScript', LuaShared.Function_StopHScript);
		s.set('Function_StopAll', LuaShared.Function_StopAll);

		s.set('setVar', function(name:String, value:Dynamic) { LuaShared.variables.set(name, value); return value; });
		s.set('getVar', function(name:String) { return LuaShared.variables.exists(name) ? LuaShared.variables.get(name) : null; });
		s.set('removeVar', function(name:String) {
			if (LuaShared.variables.exists(name)) { LuaShared.variables.remove(name); return true; }
			return false;
		});
		s.set('debugPrint', function(text:String, ?color:Int = null) {
			if (color == null) color = FlxColor.WHITE;
			try PlayState.instance.scripts.call('addTextToDebug', [text, color]) catch (e:Dynamic) trace(text);
		});

		s.set('createGlobalCallback', function(name:String, func:Dynamic) {
			for (lua in LuaShared.all)
				if (lua != null && !lua.closed && lua.L != null) lua.addCallback(name, func);
			LuaShared.customFunctions.set(name, func);
		});
		s.set('createCallback', function(name:String, func:Dynamic, ?target:Dynamic = null) {
			if (target == null) target = self;
			if (target != null) target.addCallback(name, func);
			else LuaShared.luaTrace('createCallback ($name): 3rd argument is null');
		});

		s.set('addHaxeLibrary', function(libName:String, ?libPackage:String = '') {
			var str:String = (libPackage != null && libPackage.length > 0) ? libPackage + '.' : '';
			var c:Dynamic = Type.resolveClass(str + libName);
			if (c == null) c = Type.resolveEnum(str + libName);
			if (c != null) s.set(libName, c);
		});

		for (name in funk.hscriptLibs.keys()) s.set(name, funk.hscriptLibs.get(name));

		if (varsToBring != null)
			for (key in Reflect.fields(varsToBring))
				s.set(StringTools.trim(key), Reflect.field(varsToBring, key));
	}

	public static function fixParamCapture(funk:Dynamic, code:String):String {
		var re:EReg = LuaHaxe.reFn;
		var ident:EReg = LuaHaxe.reIdent;
		return re.map(code, function(r:EReg):String {
			var raw:String = r.matched(2);
			var params:Array<String> = [];
			for (x in raw.split(',')) {
				var t:String = StringTools.trim(x);
				if (t.length > 0) params.push(t);
			}
			if (params.length == 0) return r.matched(0);
			for (t in params) if (!ident.match(t)) return r.matched(0);
			var names:Array<String> = [];
			var decl:String = '';
			for (t in params) {
				names.push('__p_' + t);
				decl += ' var ' + t + ' = __p_' + t + ';';
			}
			return 'function ' + r.matched(1) + '(' + names.join(', ') + ') {' + decl;
		});
	}

	public static function runHaxeCode(funk:Dynamic, code:String, ?varsToBring:Dynamic = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
		if (code == null) return null;
		if (LuaHaxe.reFastCam.match(code) && PlayState.instance != null) {
			var d:String = StringTools.replace(StringTools.replace(LuaHaxe.reFastCam.matched(1), "'", ""), "\"", "");
			var g:Dynamic = PlayState.instance;
			var o:Int = g.curCameraTarget;
			g.curCameraTarget = (d == 'true' || d == 'dad') ? 0 : ((d == 'gf') ? 2 : 1);
			LuaHaxe.camProbe = true;
			try g.moveCamera() catch (e:Dynamic) { LuaShared.luaTrace('moveCamera: ' + Std.string(e)); }
			LuaHaxe.camProbe = false;
			g.curCameraTarget = o;
			return null;
		}
		try code = LuaHaxe.fixParamCapture(funk, code) catch (e:Dynamic) {}
		try code = LuaHaxe.shimPsychHaxe(funk, code) catch (e:Dynamic) {}
		if ((funcToRun == null || funcToRun.length == 0) && code.indexOf('return') >= 0 && code.indexOf('function') < 0 && code.indexOf('import ') < 0) {
			code = 'function __luaMain() {\n' + code + '\n}';
			funcToRun = '__luaMain';
		}
		if (funk.hscript != null) { try funk.hscript.destroy() catch (e:Dynamic) {} funk.hscript = null; }
		try {
			var s:Dynamic = Script.fromString(code, funk.scriptName + '.hx');
			LuaHaxe.presetHScript(funk, s, varsToBring);
			s.load();
			funk.hscript = s;
		} catch (e:Dynamic) {
			LuaShared.luaTrace('runHaxeCode: ' + Std.string(e));
			funk.hscript = null;
			return null;
		}
		if (funcToRun != null && funcToRun.length > 0) return LuaHaxe.hscriptCall(funk, funcToRun, funcArgs);
		return null;
	}

	public static function hscriptCall(funk:Dynamic, func:String, ?args:Array<Dynamic> = null):Dynamic {
		if (funk.hscript == null || func == null) return null;
		try {
			var ret:Dynamic = funk.hscript.call(func, args == null ? [] : args);
			return LuaShared.isLuaSupported(ret) ? ret : null;
		} catch (e:Dynamic) {
			LuaShared.luaTrace('runHaxeFunction ($func): ' + Std.string(e));
		}
		return null;
	}
}
