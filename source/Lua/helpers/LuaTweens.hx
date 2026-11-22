package lua.helpers;

import funkin.game.PlayState;
import Utils.LuaUtils;
import lua.helpers.LuaShared;
import lua.helpers.LuaProps;

using StringTools;

class LuaTweens {

	public static function tweenPrepare(funk:Dynamic, tag:String, vars:String):Dynamic {
		if (tag != null) {
			var k:String = LuaUtils.formatVariable('tween_' + tag);
			var old:Dynamic = LuaShared.variables.get(k);
			if (old != null) { try old.cancel() catch (e:Dynamic) {} LuaShared.variables.remove(k); }
		}
		var t:Dynamic = LuaProps.resolveObject(funk, vars);
		if (t != null) return t;
		try { return LuaUtils.tweenPrepare(null, vars); } catch (e:Dynamic) {}
		return null;
	}

	public static function cancelTweenSafe(funk:Dynamic, tag:String):Void {
		if (tag == null) return;
		var key:String = LuaUtils.formatVariable('tween_$tag');
		var old:Dynamic = LuaShared.variables.get(key);
		if (old == null) { try LuaUtils.cancelTween(tag) catch (e:Dynamic) {} return; }
		try { Reflect.setProperty(old, 'onComplete', null); } catch (e:Dynamic) {}
		try { Reflect.setProperty(old, 'onUpdate', null); } catch (e:Dynamic) {}
		try old.cancel() catch (e:Dynamic) {}
		LuaShared.variables.remove(key);
	}

	public static function tweenReallyDone(funk:Dynamic, twn:Dynamic):Bool {
		try {
			var pct:Dynamic = Reflect.getProperty(twn, 'percent');
			if (pct != null && Std.parseFloat(Std.string(pct)) < 0.999) return false;
		} catch (e:Dynamic) {}
		return true;
	}

	public static function noteTweenFunction(funk:Dynamic, tag:String, note:Int, data:Dynamic, duration:Float, ease:String):Dynamic {
		var funk = funk;
		var tag = tag;  
		if (PlayState.instance == null) return null;
		var strum:Dynamic = LuaProps.getStrum(funk, note);
		if (strum == null) return null;

		if (tag != null) {
			var originalTag:String = tag;
			LuaTweens.cancelTweenSafe(funk, originalTag);
			tag = LuaUtils.formatVariable('tween_$tag');
			var variables = LuaShared.variables;
			variables.set(tag, FlxTween.tween(strum, data, duration, {
				ease: LuaUtils.getTweenEaseByString(ease),
				onComplete: function(twn:FlxTween) {
					if (!LuaTweens.tweenReallyDone(funk, twn)) return;
					variables.remove(tag);
					LuaShared.callOnAll('onTweenCompleted', [originalTag]);
				}
			}));
			return tag;
		}
		FlxTween.tween(strum, data, duration, {ease: LuaUtils.getTweenEaseByString(ease)});
		return null;
	}

	public static function oldTweenFunction(funk:Dynamic, tag:String, vars:String, tweenValue:Dynamic, duration:Float, ease:String, funcName:String):Dynamic {
		var funk = funk;  
		var tag = tag;   
		var vars = vars;  
		var tweenValue = tweenValue;  
		var funcName = funcName;
		var duration = duration;
		var target:Dynamic = LuaTweens.tweenPrepare(funk, tag, vars);
		var variables = LuaShared.variables;
		if (target != null) {
			if (tag != null) {
				var originalTag:String = tag;
				tag = LuaUtils.formatVariable('tween_$tag');
				if (funcName == 'doTweenAlpha') {
					var a0:Dynamic = null;
					try a0 = Reflect.getProperty(target, 'alpha') catch (e:Dynamic) {}
				}
				variables.set(tag, FlxTween.tween(target, tweenValue, duration, {
					ease: LuaUtils.getTweenEaseByString(ease),
					onComplete: function(twn:FlxTween) {
						variables.remove(tag);
						try {
							for (f in Reflect.fields(tweenValue)) Reflect.setProperty(target, f, Reflect.field(tweenValue, f));
						} catch (e:Dynamic) {}
						if (funcName == 'doTweenAlpha') {
							var now:Dynamic = null;
							try now = Reflect.getProperty(target, 'alpha') catch (e:Dynamic) {}
						}
						LuaShared.callOnAll('onTweenCompleted', [originalTag, vars]);
					}
				}));
				return tag;
			}
			FlxTween.tween(target, tweenValue, duration, {ease: LuaUtils.getTweenEaseByString(ease)});
		}
		return null;
	}

	public static function tweenTypeFromString(funk:Dynamic, t:String):FlxTweenType {
		if (t == null) return 8;
		switch (t.toLowerCase().trim()) {
			case 'backward': return 16;
			case 'looping': return 2;
			case 'persist': return 1;
			case 'pingpong': return 4;
			default: return 8;
		}
	}

	public static function noteTweenDirectionFunction(funk:Dynamic, tag:String, note:Int, value:Float, duration:Float, ease:String):Dynamic {
		var funk = funk; 
		var tag = tag;  
		if (PlayState.instance == null) return null;
		var strum:Dynamic = LuaProps.getStrum(funk, note);
		if (strum == null) return null;

		var current:Float = strum.noteAngle != null ? strum.noteAngle : strum.angle;
		var proxy:Dynamic = {d: current + 90};
		var apply:FlxTween->Void = function(twn:FlxTween) {
			strum.noteAngle = proxy.d - 90;
		};

		var variables = LuaShared.variables;
		var originalTag:String = tag;
		if (tag != null) {
			LuaTweens.cancelTweenSafe(funk, originalTag);
			tag = LuaUtils.formatVariable('tween_$tag');
		}
		var tw:FlxTween = FlxTween.tween(proxy, {d: value}, duration, {
			ease: LuaUtils.getTweenEaseByString(ease),
			onUpdate: apply,
			onComplete: function(twn:FlxTween) {
				if (!LuaTweens.tweenReallyDone(funk, twn)) return;
				apply(twn);
				if (originalTag != null) {
					variables.remove(tag);
					LuaShared.callOnAll('onTweenCompleted', [originalTag]);
				}
			}
		});
		if (originalTag != null) {
			variables.set(tag, tw);
			return tag;
		}
		return null;
	}
}
