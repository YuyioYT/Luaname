import funkin.backend.chart.EventsData;
import funkin.editors.charter.Charter;
import funkin.backend.assets.ModsFolder;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/////////////This basically port the events to codename 

var __luaEvents:Array<String> = null;

var eventFolders:Array<String> = ['data/events/', 'custom_events/', 'songs/data/events/', 'songs/custom_events/'];

function __normEvent(n:String):String return StringTools.replace(n, '_', ' ').toLowerCase();

function __addEventName(names:Array<String>, norms:Array<String>, n:String) {
	if (n == null) return;
	n = StringTools.trim(n);
	if (n == '') return;
	var k:String = __normEvent(n);
	if (norms.contains(k)) return;
	norms.push(k);
	names.push(n);
}

function __isIdent(ch:String):Bool {
	if (ch == null || ch == '') return false;
	var c:Int = ch.charCodeAt(0);
	return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
}

function __scanOnEvent(txt:String, names:Array<String>, norms:Array<String>) {
	var i:Int = txt.indexOf('function onEvent');
	if (i < 0) return;
	var j:Int = txt.indexOf('\nfunction ', i + 10);
	var region:String = j < 0 ? txt.substr(i) : txt.substring(i, j);
	var pos:Int = 0;
	while (true) {
		var k:Int = region.indexOf('==', pos);
		if (k < 0) break;
		pos = k + 2;

		var a:Int = k - 1;
		while (a >= 0 && region.charAt(a) == ' ') a--;
		var e:Int = a;
		while (a >= 0 && __isIdent(region.charAt(a))) a--;
		var lhs:String = region.substring(a + 1, e + 1);
		if (lhs != 'name' && lhs != 'eventName') continue;

		var b:Int = k + 2;
		while (b < region.length && region.charAt(b) == ' ') b++;
		var q:String = region.charAt(b);
		if (q != '"' && q != "'") continue;
		var c:Int = region.indexOf(q, b + 1);
		if (c < 0) continue;
		__addEventName(names, norms, region.substring(b + 1, c));
	}
}

function __scanLuaEvents() {
	var names:Array<String> = [];
	var norms:Array<String> = [];
	var luaTexts:Array<String> = [];
	for (folder in eventFolders) {
		try {
			for (file in Paths.getFolderContent(folder, true)) {
				var ext:String = Path.extension(file).toLowerCase();
				if (ext != 'lua' && ext != 'txt') continue;
				__addEventName(names, norms, CoolUtil.getFilename(file));
				if (ext == 'lua') {
					try {
						var txt:String = Assets.exists(file) ? Assets.getText(file) : Assets.getText(Paths.getPath(folder + Path.withoutDirectory(file)));
						if (txt != null) luaTexts.push(txt);
					} catch (e:Dynamic) {}
				}
			}
		} catch (e:Dynamic) {}
	}
	for (txt in luaTexts) {
		try { __scanOnEvent(txt, names, norms); } catch (e:Dynamic) {}
	}
	__luaEvents = names;
}

function __ensureLuaIcon(n:String) {
	try {
		var dir:String = ModsFolder.modsPath + ModsFolder.currentModFolder + '/images/editors/charter/event-icons/';
		var src:String = dir + 'Lua.png';
		var dst:String = dir + n + '.png';
		if (FileSystem.exists(src) && !FileSystem.exists(dst)) File.copy(src, dst);
	} catch (e:Dynamic) {
		trace('[Lua] Could not create icon for ' + n + ': ' + Std.string(e) + 'Null');
	}
}

function __registerLuaEvents() {
	if (__luaEvents == null) __scanLuaEvents();
	if (__luaEvents.length == 0) return;

	var tString = EventsData.defaultEventsParams.get('HScript Call')[0].type;

	for (n in __luaEvents) {
		__ensureLuaIcon(n);
		if (EventsData.eventsList.contains(n)) continue;
		EventsData.eventsList.push(n);
		EventsData.eventsParams.set(n, [
			{name: 'Value 1', type: tString, defValue: ''},
			{name: 'Value 2', type: tString, defValue: ''}
		]);
	}
}

function postStateSwitch() {
	__registerLuaEvents();
}

function postUpdate(elapsed:Float) {
	if (__luaEvents != null && __luaEvents.length > 0 && Std.isOfType(FlxG.state, Charter))
		if (!EventsData.eventsList.contains(__luaEvents[0])) __registerLuaEvents();
}

function destroy() {
	__luaEvents = null;
}
