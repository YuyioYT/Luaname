package Utils;

import flixel.util.FlxColor;

using StringTools;


///////////////// PORT BY YUYIO, CREDITS TO PSYCH ENGINE 

class CoolUtil2 {
    public static function colorFromString(color:String):FlxColor {
		color = color.split("\t").join("").split("\n").join("").split("\r").join("").trim();
		if (color.startsWith('0x'))
			color = color.substring(color.length - 6);

		var colorNum:Null<FlxColor> = FlxColor.fromString(color);
		if (colorNum == null)
			colorNum = FlxColor.fromString('#$color');
		return colorNum != null ? colorNum : FlxColor.WHITE;
    }
}
