package lua.helpers;

import funkin.game.PlayState;
import funkin.backend.assets.Paths;
import openfl.utils.Assets;
import haxe.ds.StringMap;
import sys.FileSystem;

using StringTools;

/////////////Do i have to explain this?
class LuaFiles {

	public static var fileCache:StringMap<String> = new StringMap<String>();

	public static function findFile(funk:Dynamic, path:String, absolute:Bool):String {
		if (path == null || path.length < 1) return null;
		var cacheKey:String = (absolute ? 'A|' : 'R|') + Std.string(funk.modFolder) + '|' + path;
		var cached:String = LuaFiles.fileCache.get(cacheKey);
		if (cached != null) return cached;
		var found:String = LuaFiles.findFileUncached(funk, path, absolute);
		if (found != null) LuaFiles.fileCache.set(cacheKey, found);
		return found;
	}

	public static function findFileUncached(funk:Dynamic, path:String, absolute:Bool):String {
		if (path == null || path.length < 1) return null;
		var clean:String = path.replace('\\', '/');
		if (absolute) return FileSystem.exists(clean) ? clean : null;
		var cands:Array<String> = [];
		try cands.push(Paths.getPath(clean)) catch (e:Dynamic) {}
		cands.push(clean);
		if (funk.modFolder != null) {
			cands.push('mods/' + funk.modFolder + '/' + clean);
			cands.push('./mods/' + funk.modFolder + '/' + clean);
		}
		cands.push('mods/' + clean);
		cands.push('assets/' + clean);
		cands.push('./assets/' + clean);
		for (pre in ['data/', 'data/lua/', 'data/scripts/', 'data/lua/scripts/']) {
			try cands.push(Paths.getPath(pre + clean)) catch (e:Dynamic) {}
			if (funk.modFolder != null) cands.push('mods/' + funk.modFolder + '/' + pre + clean);
		}
		try {
			var id:String = PlayState.instance.curSongID;
			if (id != null && id.length > 0) {
				try cands.push(Paths.getPath('songs/' + id + '/' + clean)) catch (e:Dynamic) {}
				if (funk.modFolder != null) cands.push('mods/' + funk.modFolder + '/songs/' + id + '/' + clean);
			}
		} catch (e:Dynamic) {}
		for (c in cands) {
			if (c == null) continue;
			try { if (Assets.exists(c)) return c; } catch (e:Dynamic) {}
			try { if (FileSystem.exists(c) && !FileSystem.isDirectory(c)) return c; } catch (e:Dynamic) {}
		}
		return null;
	}

	public static function findScript(funk:Dynamic, scriptFile:String, ?ext:String = '.lua'):String {
		if (!scriptFile.endsWith(ext)) scriptFile += ext;
		var candidates:Array<String> = [scriptFile, 'data/lua/' + scriptFile, 'data/lua/scripts/' + scriptFile, 'data/scripts/' + scriptFile];
		try {
			var id:String = PlayState.instance.curSongID;
			if (id != null && id.length > 0) candidates.push('songs/' + id + '/scripts/' + scriptFile);
		} catch (e:Dynamic) {}
		for (c in candidates) {
			var p:String = Paths.getPath(c);
			if (Assets.exists(p)) return p;
		}
		return null;
	}
}
