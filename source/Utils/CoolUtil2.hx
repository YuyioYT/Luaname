package Utils;

import flixel.util.FlxColor;
import flixel.util.FlxSave;
import flixel.text.FlxTextBorderStyle;

using StringTools;
///////////////// PORT BY YUYIO, CREDITS TO PSYCH ENGINE 

class CoolUtil2 {
    public static function colorFromString(color:String):FlxColor {
		if (color == null || color == "") return FlxColor.WHITE;
		color = color.split("\t").join("").split("\n").join("").split("\r").join("").trim();
		if (color.startsWith('0x'))
			color = color.substring(color.length - 6);

		var colorNum:Null<FlxColor> = FlxColor.fromString(color);
		if (colorNum == null)
			colorNum = FlxColor.fromString('#$color');
		return colorNum != null ? colorNum : FlxColor.WHITE;
    }

	public static function getSavePath():String {
		var company:String = FlxG.stage.application.meta.get('company');
		// #if (flixel < "5.0.0") return company; #else
		return '${company}/${FlxSave.validate(FlxG.stage.application.meta.get('file'))}';
		// #end
	}

	public static function setTextBorderFromString(text:FlxText, border:String)
	{
		switch(border.toLowerCase().trim())
		{
			case 'shadow':
				text.borderStyle = FlxTextBorderStyle.SHADOW;
			case 'outline':
				text.borderStyle = FlxTextBorderStyle.OUTLINE;
			case 'outline_fast':
				text.borderStyle = FlxTextBorderStyle.OUTLINE_FAST;
			default:
				text.borderStyle = FlxTextBorderStyle.NONE;
		}
	}

	public static function browserLoad(site:String) {
		#if linux
		Sys.command('/usr/bin/xdg-open', [site]);
		#else
		FlxG.openURL(site);
		#end
	}
}
