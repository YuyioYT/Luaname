package lua.helpers;

import funkin.game.PlayState;
import funkin.game.Character;
import funkin.backend.assets.Paths;
import openfl.utils.Assets;
import lua.helpers.LuaShared;
import funkin.backend.utils.CoolUtil;

using StringTools;

///////////Convert the xml to psych json
class LuaCharacters {
	public static function psychCharName(funk:Dynamic, path:String):String {
		if (path == null) return null;
		var clean:String = path.replace('\\', '/');
		if (!clean.toLowerCase().endsWith('.json')) return null;
		var parts:Array<String> = clean.split('/');
		if (parts.length < 2 || parts[parts.length - 2].toLowerCase() != 'characters') return null;
		var file:String = parts[parts.length - 1];
		return file.substr(0, file.length - 5);
	}

	public static function psychCharXmlPath(funk:Dynamic, path:String):String {
		var name:String = LuaCharacters.psychCharName(funk, path);
		if (name == null || name.length < 1) return null;
		try {
			var xp:String = Paths.xml('characters/' + name);
			if (Assets.exists(xp)) return xp;
		} catch (e:Dynamic) {}
		return null;
	}

	public static function xmlAttr(funk:Dynamic, node:Xml, name:String, ?def:String = null):String {
		return node.exists(name) ? node.get(name) : def;
	}

	public static function xmlFloat(funk:Dynamic, node:Xml, name:String, def:Float):Float {
		var v:String = LuaCharacters.xmlAttr(funk, node, name);
		if (v == null) return def;
		var f:Float = Std.parseFloat(v);
		return Math.isNaN(f) ? def : f;
	}

	public static function psychCharJson(funk:Dynamic, path:String):String {
		var xp:String = LuaCharacters.psychCharXmlPath(funk, path);
		if (xp == null) return null;
		var name:String = LuaCharacters.psychCharName(funk, path);
		try {
			var root:Xml = Xml.parse(Assets.getText(xp)).firstElement();
			if (root == null) return null;

			var anims:Array<Dynamic> = [];
			for (n in root.elements()) {
				if (n.nodeName != 'anim') continue;
				var indices:Array<Int> = [];
				var idx:String = LuaCharacters.xmlAttr(funk, n, 'indices');
				if (idx != null && idx.length > 0) {
					try indices = CoolUtil.parseNumberRange(idx) catch (e:Dynamic) {}
				}
				anims.push({
					anim: LuaCharacters.xmlAttr(funk, n, 'name', ''),
					name: LuaCharacters.xmlAttr(funk, n, 'anim', ''),
					fps: Std.int(LuaCharacters.xmlFloat(funk, n, 'fps', 24)),
					loop: LuaCharacters.xmlAttr(funk, n, 'loop', 'false') == 'true',
					indices: indices,
					offsets: [LuaCharacters.xmlFloat(funk, n, 'x', 0), LuaCharacters.xmlFloat(funk, n, 'y', 0)]
				});
			}

			var rgb:Array<Int> = [161, 161, 161];
			var col:String = LuaCharacters.xmlAttr(funk, root, 'color');
			if (col != null) {
				try {
					var c:FlxColor = FlxColor.fromString(col);
					if (c != null) rgb = [c.red, c.green, c.blue];
				} catch (e:Dynamic) {}
			}

			var posX:Float = LuaCharacters.xmlFloat(funk, root, 'x', 0);
			var posY:Float = LuaCharacters.xmlFloat(funk, root, 'y', 0);
			var usedAsPlayer:Bool = LuaCharacters.xmlAttr(funk, root, 'isPlayer', 'false') == 'true';
			try {
				var g:Dynamic = PlayState.instance;
				if (g != null) {
					for (c in [g.boyfriend, g.dad, g.gf]) {
						if (c != null && Std.isOfType(c, Character) && c.curCharacter == name) {
							usedAsPlayer = (c.isPlayer == true);
							break;
						}
					}
				}
			} catch (e:Dynamic) {}
			if (usedAsPlayer != (LuaCharacters.xmlAttr(funk, root, 'isPlayer', 'false') == 'true')) posX = -posX;

			var sprite:String = LuaCharacters.xmlAttr(funk, root, 'sprite', name);
			var data:Dynamic = {
				animations: anims,
				vocals_file: '',
				no_antialiasing: LuaCharacters.xmlAttr(funk, root, 'antialiasing', 'true') == 'false',
				image: 'characters/' + sprite,
				position: [posX, posY],
				healthicon: LuaCharacters.xmlAttr(funk, root, 'icon', name),
				flip_x: LuaCharacters.xmlAttr(funk, root, 'flipX', 'false') == 'true',
				healthbar_colors: rgb,
				camera_position: [LuaCharacters.xmlFloat(funk, root, 'camx', 0), LuaCharacters.xmlFloat(funk, root, 'camy', 0)],
				sing_duration: LuaCharacters.xmlFloat(funk, root, 'holdTime', 4),
				scale: LuaCharacters.xmlFloat(funk, root, 'scale', 1),
				_editor_isPlayer: LuaCharacters.xmlAttr(funk, root, 'isPlayer', 'false') == 'true'
			};
			return haxe.Json.stringify(data);
		} catch (e:Dynamic) {
			LuaShared.luaTrace('getTextFromFile: cant convert ' + xp + ' to JSON of Psych: ' + Std.string(e), false, false, FlxColor.YELLOW);
		}
		return null;
	}
}
