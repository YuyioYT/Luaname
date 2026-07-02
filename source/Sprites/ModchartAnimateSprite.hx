package Sprites;

import haxe.ds.StringMap;
import flixel.graphics.FlxGraphic;


///////////////// PORT BY YUYIO, CREDITS TO PSYCH ENGINE 

class ModchartAnimateSprite extends FlxAnimate
{
	public var animOffsets:StringMap<String, Array<Float>> = new StringMap<String, Array<Float>>();
	public function new(?x:Float = 0, ?y:Float = 0)
	{
		super(x, y);
		antialiasing = Options.antialiasing;
	}

	public function playAnim(name:String, forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0)
	{
		anim.play(name, forced, reverse, startFrame);
		
		var daOffset = animOffsets.get(name);
		if (animOffsets.exists(name)) offset.set(daOffset[0], daOffset[1]);
	}

	public function addOffset(name:String, x:Float, y:Float)
	{
		animOffsets.set(name, [x, y]);
	}
}