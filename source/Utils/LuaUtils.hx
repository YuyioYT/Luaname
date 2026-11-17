package Utils;

import Sprites.ModchartSprite;
import funkin.backend.MusicBeatState;
import funkin.play.PlayState;

import openfl.display.BlendMode;

using StringTools;


///////////////// PORT BY YUYIO, CREDITS TO PSYCH ENGINE 

class LuaUtils {
    public static function destroyObject(tag:String) {
        var variables = getVariables();
        var obj:FlxSprite = variables.get(tag);
        if (obj == null || obj.destroy == null)
            return;

        getTargetInstance().remove(obj, true);
        obj.destroy();
        variables.remove(tag);
    }

    public static function getPropertyLoop(split:Array<String>, ?getProperty:Bool = true, ?allowMaps:Bool = false):Dynamic {
        var obj:Dynamic = getObjectDirectly(split[0]);
        var end = split.length;
        if (getProperty) end = split.length - 1;

        for (i in 1...end) obj = getVarInArray(obj, split[i], allowMaps);
        return obj;
    }

    public static function getObjectDirectly(objectName:String, ?allowMaps:Bool = false):Dynamic {
        switch (objectName) {
            case "this", "instance", "game":
                return PlayState.instance;

            default:
                var obj:Dynamic = getVariables().get(objectName);
                if (obj == null) obj = getVarInArray(getState(), objectName, allowMaps);
                return obj;
        }
    }

    public static function getTargetInstance() {
        return getState();
    }

    function loadFrames(spr:FlxSprite, image:String, spriteType:String)
	{
		if (spriteType == null) spriteType = 'sparrow';
		switch(spriteType.toLowerCase().replace(' ', ''))
		{
			//case "texture" | "textureatlas" | "tex":
				//spr.frames = AtlasFrameMaker.construct(image);

			//case "texture_noaa" | "textureatlas_noaa" | "tex_noaa":
				//spr.frames = AtlasFrameMaker.construct(image, null, true);

			case 'aseprite', 'ase', 'json', 'jsoni8':
				spr.frames = Paths.getAsepriteAtlas(image);

			case "packer", 'packeratlas', 'pac':
				spr.frames = Paths.getPackerAtlas(image);

			case 'sparrow', 'sparrowatlas', 'sparrowv2':
				spr.frames = Paths.getSparrowAtlas(image);

			default:
				spr.frames = Paths.getSparrowAtlas(image);
		}
	}

    public static inline function getLowestCharacterGroup():FlxSpriteGroup
	{
		var group:FlxSpriteGroup = (PlayState.instance.gf);

		var pos:Int = PlayState.instance.members.indexOf(group);

		var newPos:Int = PlayState.instance.members.indexOf(PlayState.instance.boyfriend);
		if(newPos < pos)
		{
			group = PlayState.instance.boyfriend;
			pos = newPos;
		}
		
		newPos = PlayState.instance.members.indexOf(PlayState.instance.dad);
		if(newPos < pos)
		{
			group = PlayState.instance.dad;
			pos = newPos;
		}
		return group;
	}

    public static function getTweenEaseByString(?ease:String = '') {
		if (ease == null) ease = '';
		switch(ease.toLowerCase().trim()) {
			case 'backin': return FlxEase.backIn;
			case 'backinout': return FlxEase.backInOut;
			case 'backout': return FlxEase.backOut;
			case 'bouncein': return FlxEase.bounceIn;
			case 'bounceinout': return FlxEase.bounceInOut;
			case 'bounceout': return FlxEase.bounceOut;
			case 'circin': return FlxEase.circIn;
			case 'circinout': return FlxEase.circInOut;
			case 'circout': return FlxEase.circOut;
			case 'cubein': return FlxEase.cubeIn;
			case 'cubeinout': return FlxEase.cubeInOut;
			case 'cubeout': return FlxEase.cubeOut;
			case 'elasticin': return FlxEase.elasticIn;
			case 'elasticinout': return FlxEase.elasticInOut;
			case 'elasticout': return FlxEase.elasticOut;
			case 'expoin': return FlxEase.expoIn;
			case 'expoinout': return FlxEase.expoInOut;
			case 'expoout': return FlxEase.expoOut;
			case 'quadin': return FlxEase.quadIn;
			case 'quadinout': return FlxEase.quadInOut;
			case 'quadout': return FlxEase.quadOut;
			case 'quartin': return FlxEase.quartIn;
			case 'quartinout': return FlxEase.quartInOut;
			case 'quartout': return FlxEase.quartOut;
			case 'quintin': return FlxEase.quintIn;
			case 'quintinout': return FlxEase.quintInOut;
			case 'quintout': return FlxEase.quintOut;
			case 'sinein': return FlxEase.sineIn;
			case 'sineinout': return FlxEase.sineInOut;
			case 'sineout': return FlxEase.sineOut;
			case 'smoothstepin': return FlxEase.smoothStepIn;
			case 'smoothstepinout': return FlxEase.smoothStepInOut;
			case 'smoothstepout': return FlxEase.smoothStepOut;
			case 'smootherstepin': return FlxEase.smootherStepIn;
			case 'smootherstepinout': return FlxEase.smootherStepInOut;
			case 'smootherstepout': return FlxEase.smootherStepOut;
		}
		return FlxEase.linear;
	}

	public static function blendModeFromString(blend:String):BlendMode {
		if (blend == null) return BlendMode.NORMAL;
		switch(blend.toLowerCase().trim()) {
			case 'add': return BlendMode.ADD;
			case 'alpha': return BlendMode.ALPHA;
			case 'darken': return BlendMode.DARKEN;
			case 'difference': return BlendMode.DIFFERENCE;
			case 'erase': return BlendMode.ERASE;
			case 'hardlight': return BlendMode.HARDLIGHT;
			case 'invert': return BlendMode.INVERT;
			case 'layer': return BlendMode.LAYER;
			case 'lighten': return BlendMode.LIGHTEN;
			case 'multiply': return BlendMode.MULTIPLY;
			case 'overlay': return BlendMode.OVERLAY;
			case 'screen': return BlendMode.SCREEN;
			case 'shader': return BlendMode.SHADER;
			case 'subtract': return BlendMode.SUBTRACT;
		}
		return BlendMode.NORMAL;
	}

    public static function formatVariable(tag:String)
		return tag.trim().replace(' ', '_').replace('.', '');

    public static function cancelTween(tag:String) {
		if(!tag.startsWith('tween_')) tag = 'tween_' + LuaUtils.formatVariable(tag);
		var variables = getVariables();
		var twn:FlxTween = variables.get(tag);
		if(twn != null)
		{
			twn.cancel();
			twn.destroy();
			variables.remove(tag);
		}
	}

	public static function cancelTimer(tag:String) {
		if(!tag.startsWith('timer_')) tag = 'timer_' + LuaUtils.formatVariable(tag);
		var variables = getVariables();
		var tmr:FlxTimer = variables.get(tag);
		if(tmr != null)
		{
			tmr.cancel();
			tmr.destroy();
			variables.remove(tag);
		}
	}

    public static function tweenPrepare(tag:String, vars:String) {
		if(tag != null) LuaUtils.cancelTween(tag);
		var variables:Array<String> = vars.split('.');
		var sexyProp:Dynamic = getObjectDirectly(variables[0]);
		if(variables.length > 1) sexyProp = getVarInArray(LuaUtils.getPropertyLoop(variables), variables[variables.length-1]);
		return sexyProp;
	}

	public static function cameraFromString(cam:String):FlxCamera {
		switch(cam.toLowerCase()) {
			case 'camgame' | 'game': return PlayState.instance.camGame;
			case 'camhud' | 'hud': return PlayState.instance.camHUD;
			case 'camother' | 'other': return PlayState.instance.camOther;
		}
		var camera:FlxCamera = getVariables().get(cam);
		if (camera == null || !Std.isOfType(camera, FlxCamera)) camera = PlayState.instance.camGame;
		return camera;
	}
}
