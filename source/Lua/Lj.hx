package lua;

import funkin.backend.utils.NdllUtil;

///link ndll luajit
class Lj {
	static var ready:Bool = false;

	static var f_newstate:Dynamic;
	static var f_close:Dynamic;
	static var f_openlibs:Dynamic;
	static var f_gettop:Dynamic;
	static var f_settop:Dynamic;
	static var f_pop:Dynamic;
	static var f_type:Dynamic;
	static var f_isfunction:Dynamic;
	static var f_tonumber:Dynamic;
	static var f_tostring:Dynamic;
	static var f_toboolean:Dynamic;
	static var f_objlen:Dynamic;
	static var f_next:Dynamic;
	static var f_pushnil:Dynamic;
	static var f_pushnumber:Dynamic;
	static var f_pushboolean:Dynamic;
	static var f_pushstring:Dynamic;
	static var f_createtable:Dynamic;
	static var f_rawseti:Dynamic;
	static var f_rawgeti:Dynamic;
	static var f_setfield:Dynamic;
	static var f_getglobal:Dynamic;
	static var f_setglobal:Dynamic;
	static var f_pcall:Dynamic;
	static var f_dofile:Dynamic;
	static var f_add_cb:Dynamic;
	static var f_set_cbs:Dynamic;
	static var f_trace_func:Dynamic;
	static var f_trace_lib:Dynamic;

	public static function osName():String {
		#if windows return 'windows';
		#elseif linux return 'linux';
		#elseif mac return 'mac';
		#elseif android return 'android';
		#elseif ios return 'ios';
		#else return 'unknown';
		#end
	}

	public static function init():Void {
		if (ready) return;
		ready = true;
		var f = function(name:String, args:Int):Dynamic return NdllUtil.getFunction("luajit", name, args);

		f_newstate     = f("lj_newstate", 0);
		f_close        = f("lj_close", 1);
		f_openlibs     = f("lj_openlibs", 1);
		f_gettop       = f("lj_gettop", 1);
		f_settop       = f("lj_settop", 2);
		f_pop          = f("lj_pop", 2);
		f_type         = f("lj_type", 2);
		f_isfunction   = f("lj_isfunction", 2);
		f_tonumber     = f("lj_tonumber", 2);
		f_tostring     = f("lj_tostring", 2);
		f_toboolean    = f("lj_toboolean", 2);
		f_objlen       = f("lj_objlen", 2);
		f_next         = f("lj_next", 2);
		f_pushnil      = f("lj_pushnil", 1);
		f_pushnumber   = f("lj_pushnumber", 2);
		f_pushboolean  = f("lj_pushboolean", 2);
		f_pushstring   = f("lj_pushstring", 2);
		f_createtable  = f("lj_createtable", 3);
		f_rawseti      = f("lj_rawseti", 3);
		f_rawgeti      = f("lj_rawgeti", 3);
		f_setfield     = f("lj_setfield", 3);
		f_getglobal    = f("lj_getglobal", 2);
		f_setglobal    = f("lj_setglobal", 2); 
		f_pcall        = f("lj_pcall", 4);
		f_dofile       = f("lj_dofile", 2);
		f_add_cb       = f("lj_add_callback_function", 2);
		f_set_cbs      = f("lj_set_callbacks_function", 1);
		f_trace_func   = f("lj_register_hxtrace_func", 1);
		f_trace_lib    = f("lj_register_hxtrace_lib", 1);
	}

	public static inline function newstate():Dynamic return f_newstate();
	public static inline function close(L:Dynamic):Void f_close(L);
	public static inline function openlibs(L:Dynamic):Void f_openlibs(L);

	public static inline function gettop(L:Dynamic):Int return Std.int(f_gettop(L));
	public static inline function settop(L:Dynamic, i:Int):Void f_settop(L, i);
	public static inline function pop(L:Dynamic, n:Int):Void f_pop(L, n);
	public static inline function type(L:Dynamic, i:Int):Int return Std.int(f_type(L, i));
	public static inline function isfunction(L:Dynamic, i:Int):Bool return f_isfunction(L, i) == true;
	public static inline function tonumber(L:Dynamic, i:Int):Float return f_tonumber(L, i);
	public static inline function tostring(L:Dynamic, i:Int):String return f_tostring(L, i);
	public static inline function toboolean(L:Dynamic, i:Int):Bool return f_toboolean(L, i) == true;
	public static inline function objlen(L:Dynamic, i:Int):Int return Std.int(f_objlen(L, i));
	public static inline function next(L:Dynamic, i:Int):Int return Std.int(f_next(L, i));

	public static inline function pushnil(L:Dynamic):Void f_pushnil(L);
	public static inline function pushnumber(L:Dynamic, n:Float):Void f_pushnumber(L, n);
	public static inline function pushboolean(L:Dynamic, b:Bool):Void f_pushboolean(L, b);
	public static inline function pushstring(L:Dynamic, s:String):Void f_pushstring(L, s);
	public static inline function createtable(L:Dynamic, narr:Int, nrec:Int):Void f_createtable(L, narr, nrec);
	public static inline function rawseti(L:Dynamic, t:Int, n:Int):Void f_rawseti(L, t, n);
	public static inline function rawgeti(L:Dynamic, t:Int, n:Int):Void f_rawgeti(L, t, n);
	public static inline function setfield(L:Dynamic, t:Int, k:String):Void f_setfield(L, t, k);
	public static inline function getglobal(L:Dynamic, name:String):Void f_getglobal(L, name);
	public static inline function pcall(L:Dynamic, nargs:Int, nresults:Int, errfunc:Int):Int return Std.int(f_pcall(L, nargs, nresults, errfunc));
	public static inline function dofile(L:Dynamic, path:String):Int return Std.int(f_dofile(L, path));

	public static inline function addCallbackFunction(L:Dynamic, name:String):Void f_add_cb(L, name);
	public static inline function setCallbacksFunction(fn:Dynamic):Void f_set_cbs(fn);
	public static inline function registerHxtraceFunc(fn:Dynamic):Void f_trace_func(fn);
	public static inline function registerHxtraceLib(L:Dynamic):Void f_trace_lib(L);

	public static function setGlobal(L:Dynamic, name:String, value:Dynamic):Void {
		pushValue(L, value);
		f_setglobal(L, name);
	}

	public static function readValue(L:Dynamic, idx:Int, depth:Int = 0):Dynamic {
		switch (Std.int(f_type(L, idx))) {
			case 1: return f_toboolean(L, idx) == true;
			case 3: return f_tonumber(L, idx);
			case 4: return f_tostring(L, idx);
			case 5: return depth > 8 ? null : readTable(L, idx, depth);
			default: return null;
		}
	}

	static function readTable(L:Dynamic, idx:Int, depth:Int):Dynamic {
		var abs:Int = idx < 0 ? Std.int(f_gettop(L)) + idx + 1 : idx;
		var n:Int = Std.int(f_objlen(L, abs));
		if (n > 0) {
			var arr:Array<Dynamic> = [];
			for (i in 1...n + 1) {
				f_rawgeti(L, abs, i);
				arr.push(readValue(L, -1, depth + 1));
				f_pop(L, 1);
			}
			return arr;
		}
		var obj:Dynamic = {};
		f_pushnil(L);
		while (Std.int(f_next(L, abs)) != 0) {
			var kt:Int = Std.int(f_type(L, -2));
			var key:String = null;
			if (kt == 4) key = f_tostring(L, -2);
			else if (kt == 3) key = Std.string(f_tonumber(L, -2));
			if (key != null) Reflect.setField(obj, key, readValue(L, -1, depth + 1));
			f_pop(L, 1);
		}
		return obj;
	}

	public static function pushValue(L:Dynamic, v:Dynamic, depth:Int = 0):Void {
		if (v == null || depth > 8) { f_pushnil(L); return; }
		if (Std.isOfType(v, Bool)) { f_pushboolean(L, v); return; }
		if (Std.isOfType(v, Int) || Std.isOfType(v, Float)) { f_pushnumber(L, v); return; }
		if (Std.isOfType(v, String)) { f_pushstring(L, v); return; }
		if (Std.isOfType(v, Array)) {
			var a:Array<Dynamic> = v;
			f_createtable(L, a.length, 0);
			for (i in 0...a.length) {
				pushValue(L, a[i], depth + 1);
				f_rawseti(L, -2, i + 1);
			}
			return;
		}
		if (Reflect.isObject(v) && Type.getClass(v) == null && Type.getEnum(v) == null) {
			f_createtable(L, 0, 4);
			for (f in Reflect.fields(v)) {
				pushValue(L, Reflect.field(v, f), depth + 1);
				f_setfield(L, -2, f);
			}
			return;
		}
		f_pushstring(L, Std.string(v));
	}
}
