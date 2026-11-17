import funkin.backend.MusicBeatState;
import haxe.ds.StringMap;
import haxe.Reflect;


///////////////// PORT BY YUYIO, CREDITS TO PSYCH ENGINE 

public static var variables:StringMap<Dynamic> = new StringMap<Dynamic>();

public static function getVariables():StringMap<Dynamic> {
    return variables;
}

public static function getState():MusicBeatState {
    return cast(FlxG.state, MusicBeatState);
}

public static function getLuaObject(tag:String):Dynamic {
    return variables.get(tag);
}

public static function getVarInArray(obj:Dynamic, prop:String, ?allowMaps:Bool = false):Dynamic {
    if (obj == null) return null;
    
    if (Reflect.hasField(obj, prop)) {
        return Reflect.field(obj, prop);
    }
    
    if (allowMaps && Std.is(obj, StringMap)) {
        var map:StringMap<Dynamic> = cast(obj, StringMap<Dynamic>);
        if (map.exists(prop)) {
            return map.get(prop);
        }
    }
    
    return null;
}
