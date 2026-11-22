package lua.helpers;

import funkin.game.PlayState;
import flixel.input.gamepad.FlxGamepadInputID;

using StringTools;

class LuaInput {

	public static function gpId(funk:Dynamic, name:String):FlxGamepadInputID {
		return FlxGamepadInputID.fromString(name == null ? '' : name.toUpperCase());
	}

	public static function keyState(funk:Dynamic, kind:String, name:String):Bool {
		try {
			var list:Dynamic = Reflect.getProperty(FlxG.keys, kind);
			return Reflect.getProperty(list, name.toUpperCase()) == true;
		} catch (e:Dynamic) {}
		return false;
	}

	public static function controlState(funk:Dynamic, name:String, suffix:String):Bool {
		try {
			var c:Dynamic = PlayState.instance.controls;
			var n:String = name.trim().toLowerCase();
			var field:String = null;
			switch (n) {
				case 'left' | 'down' | 'up' | 'right':
					field = 'NOTE_' + n.toUpperCase() + suffix;
				case 'accept' | 'back' | 'pause' | 'reset':
					var base:String = n.toUpperCase();
					field = suffix == '_P' ? base : (suffix == '_R' ? base + '_R' : base + '_HOLD');
				case 'space':
					return LuaInput.keyState(funk, suffix == '_P' ? 'justPressed' : (suffix == '_R' ? 'justReleased' : 'pressed'), 'SPACE');
			}
			return field != null && Reflect.getProperty(c, field) == true;
		} catch (e:Dynamic) {}
		return false;
	}
}
