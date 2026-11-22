package lua.helpers;

import funkin.game.PlayState;
import funkin.backend.system.Logs;
import lua.FunkinLua;
import hxvlc.flixel.FlxVideoSprite;
import Utils.LuaUtils;
import lua.helpers.LuaShared;
import lua.helpers.LuaProps;
import lua.helpers.LuaShaders;
import funkin.backend.assets.Paths;
import openfl.utils.Assets;

using StringTools;

class LuaVideos {
	public static var videoSprite:Dynamic = null;
	public static var videoCanSkip:Bool = false;
	public static var videoName:String = null;
	public static var videoMidSong:Bool = true;

	static var videoPausedByGame:Bool = false;
	static var videoWasPlaying:Bool = true;
	static var videoPauseLogged:Bool = false;

	static function isVideoPlaying(v:Dynamic):Bool {
		try { if (v != null && v.bitmap != null) return v.bitmap.isPlaying == true; } catch (e:Dynamic) {}
		return true;
	}

	static function setVideoPaused(paused:Bool):Void {
		var v:Dynamic = videoSprite;
		if (v == null) return;
		try { if (paused) v.pause(); else v.resume(); }
		catch (e:Dynamic) { LuaShared.luaTrace('video: bug in' + (paused ? 'pause' : 'resume') + ' of sprite: ' + Std.string(e), false, false, FlxColor.RED); }
		try {
			var bm:Dynamic = v.bitmap;
			if (bm != null) {
				var playing:Bool = bm.isPlaying == true;
				if (paused && playing) bm.pause();
				else if (!paused && !playing) bm.resume();
			}
		} catch (e:Dynamic) { LuaShared.luaTrace('video: bug in ' + (paused ? 'pause' : 'resume') + ' of bitmap: ' + Std.string(e), false, false, FlxColor.RED); }
	}

	public static function pauseVideo():Void {
		var v:Dynamic = videoSprite;
		if (v == null || videoPausedByGame) return;
		videoPausedByGame = true;
		videoWasPlaying = isVideoPlaying(v);
		if (videoWasPlaying) setVideoPaused(true);
		if (!videoPauseLogged) {
			videoPauseLogged = true;
			LuaShared.luaTrace('video: paused ' + videoWasPlaying + ', now =' + isVideoPlaying(v) + ')', false, false, FlxColor.YELLOW);
		}
	}

	public static function resumeVideo():Void {
		var v:Dynamic = videoSprite;
		if (!videoPausedByGame) return;
		videoPausedByGame = false;
		if (v == null) return;
		if (videoWasPlaying) setVideoPaused(false);
		try { v.visible = true; v.alpha = 1; } catch (e:Dynamic) {}
	}

	static var videoTickCb:Dynamic = null;
	static var videoRepairLogged:Bool = false;
	static function videoTick():Void {
		var v:Dynamic = videoSprite;
		var g:PlayState = PlayState.instance;
		if (v == null || g == null) return;

		var engineP:Bool = false;
		if (g.subState != null) { try engineP = Reflect.getProperty(g, 'paused') == true catch (e:Dynamic) {} }
		if (FunkinLua.gamePaused || engineP) {

			if (!videoPausedByGame) pauseVideo();
			else if (isVideoPlaying(v)) setVideoPaused(true);

		} else if (videoPausedByGame) resumeVideo();
		if (g.subState == null) return;

		var repaired:String = '';

		if (v.exists != true) { v.exists = true; repaired += ' exists'; }
		if (v.alive != true) { v.alive = true; repaired += ' alive'; }
		if (v.visible != true) { v.visible = true; repaired += ' visible'; }
		if (v.alpha < 1) { v.alpha = 1; repaired += ' alpha'; }

		try {
			if (g.members.indexOf(v) < 0) { g.add(v); repaired += ' members'; }
			var cams:Array<Dynamic> = v.cameras;
			var ok:Bool = cams != null && cams.length > 0;
			if (ok) for (c in cams) if (c == null || !FlxG.cameras.list.contains(c)) { ok = false; break; }
			if (!ok) { v.cameras = [g.camHUD]; repaired += ' camera'; }
		} catch (e:Dynamic) {}
		if (repaired != '' && !videoRepairLogged) {
			videoRepairLogged = true;
		}
	}

	public static function stopVideo(?why:String = 'stopped'):Void {
		var v:Dynamic = videoSprite;
		if (v == null) return;
		LuaShared.luaTrace('stopVideo: ' + why, false, false, FlxColor.YELLOW);

		videoSprite = null;
		videoName = null;
		videoPausedByGame = false;

		if (videoTickCb != null) { try FlxG.signals.postUpdate.remove(videoTickCb) catch (e:Dynamic) {} videoTickCb = null; }
		var g:PlayState = PlayState.instance;

		LuaShared.variables.remove('videoCutscene');

		try {
			if (g != null) g.remove(v, true);
			v.destroy();
		} catch (e:Dynamic) {
			Logs.warn('[Lua] stopVideo: ' + Std.string(e));
		}

		if (g != null && !videoMidSong) {
			g.inCutscene = false;
			FunkinLua.countdownBlocked = false;
			if (!g.startedCountdown) g.startCountdown();
		}
	}

	static function findVideoPath(name:String):String {
		var n:String = StringTools.trim(name);
		while (n.length > 1 && (n.charAt(0) == '"' || n.charAt(0) == "'") && n.charAt(n.length - 1) == n.charAt(0)) n = n.substr(1, n.length - 2);
		n = StringTools.replace(n, '\\', '/');

		if (n.startsWith('videos/')) n = n.substr(7);

		var base:String = n;
		var dot:Int = n.lastIndexOf('.');
		var exts:Array<String> = ['mp4', 'webm', 'mov', 'mkv', 'avi', 'flv', 'mpg', 'm4v'];

		if (dot > 0 && exts.contains(n.substr(dot + 1).toLowerCase())) {
			var direct:String = Paths.getPath('videos/' + n);
			if (Assets.exists(direct)) return direct;
			base = n.substr(0, dot);
		}

		var first:String = Paths.video(base);
		if (Assets.exists(first)) return first;

		for (e in exts) {
			var p:String = Paths.video(base, e);
			if (Assets.exists(p)) return p;
		}
		return null;
	}

	public static var videoCalls:Int = 0;
	public static function start(funk:Dynamic, videoFileRaw:Dynamic, ?canSkip:Bool = true, ?forMidSong:Bool = false, ?shouldLoop:Bool = false, ?playOnLoad:Bool = true):Bool {
		videoCalls++;
		var videoFile:String = videoFileRaw == null ? null : Std.string(videoFileRaw);

		var g:PlayState = PlayState.instance;

		LuaShared.luaTrace('startVideo ("' + videoFile + '", canSkip=' + canSkip + ', midSong=' + forMidSong + ', loop=' + shouldLoop + ', play=' + playOnLoad + ')', false, false, FlxColor.GREEN);
		
		if (videoFile == null || videoFile == '') {
			LuaShared.luaTrace('startVideo: no video file specified', false, false, FlxColor.RED);
			return false;
		}

		var path:String = findVideoPath(videoFile);
		if (g == null || path == null) {
			LuaShared.luaTrace('startVideo: Couldnt find video file: ' + videoFile, false, false, FlxColor.RED);
			if (g != null && !forMidSong) { FunkinLua.countdownBlocked = false; g.startCountdown(); }
			return false;
		}

		if (videoSprite != null && videoName == path) {
			LuaShared.luaTrace('startVideo: "' + videoFile + '"video already running ignoring other video', false, false, FlxColor.YELLOW);
			return true;
		}

		videoMidSong = true;
		stopVideo();
		videoName = path;
		videoCanSkip = canSkip == true;
		videoMidSong = forMidSong == true;
		if (!videoMidSong) g.inCutscene = true;

		var vid:FlxVideoSprite = new FlxVideoSprite();
		vid.antialiasing = true;
		try Reflect.setProperty(vid, 'autoPause', false) catch (e:Dynamic) {}
		vid.scrollFactor.set(0, 0);
		vid.visible = true;
		vid.alpha = 1;
		vid.cameras = [LuaShaders.safeCam(funk, 'camOther')];
		vid.bitmap.onFormatSetup.add(function() {
			if (vid.bitmap != null && vid.bitmap.bitmapData != null) {
				var bw:Float = vid.bitmap.bitmapData.width;
				var bh:Float = vid.bitmap.bitmapData.height;
				var sc:Float = Math.min(FlxG.width / bw, FlxG.height / bh);
				vid.setGraphicSize(Std.int(bw * sc), Std.int(bh * sc));
				vid.updateHitbox();
				vid.screenCenter();
			}
		});
		vid.bitmap.onEndReached.add(function() {
			new FlxTimer().start(0.001, function(_) { if (videoSprite == vid) stopVideo('end of the video'); });
		});

		g.add(vid);
		videoSprite = vid;
		videoRepairLogged = false;
		videoPausedByGame = false;
		if (videoTickCb == null) { videoTickCb = videoTick; FlxG.signals.postUpdate.add(videoTickCb); }
		LuaShared.variables.set('videoCutscene', vid);

		var localPath:String = Assets.getPath(path);
		LuaShared.luaTrace('startVideo: cargando ' + localPath, false, false, FlxColor.GREEN);

		new FlxTimer().start(0.05, function(_) {
			if (videoSprite != vid) return;
			var ok:Bool = false;
			try {
				if (shouldLoop == true) ok = vid.load(localPath, [':input-repeat=65535']);
				else ok = vid.load(localPath);
			} catch (e:Dynamic) {
				LuaShared.luaTrace('startVideo: error loading: ' + Std.string(e), false, false, FlxColor.RED);
			}
			if (ok) {
				LuaShared.luaTrace('startVideo: video loading: ' + (playOnLoad != false), false, false, FlxColor.GREEN);
				if (playOnLoad != false) vid.play();
			} else {
				LuaShared.luaTrace('startVideo: could not load ' + videoFile + ' (' + localPath + ')', false, false, FlxColor.RED);
				if (videoSprite == vid) stopVideo('couldnt load');
			}
		});
		return true;
	}

	static function isVideo(o:Dynamic):Bool {
		return o != null && Std.isOfType(o, FlxVideoSprite);
	}

	public static function get(funk:Dynamic, tag:String):FlxVideoSprite {
		if (tag == null) return null;
		var o:Dynamic = LuaShared.variables.get(tag);
		if (o == null) {
			var split:Array<String> = tag.split('.');
			try {
				o = LuaProps.resolveObject(funk, split[0]);
				if (split.length > 1) o = LuaProps.getVarInArray(funk, LuaUtils.getPropertyLoop(split), split[split.length - 1]);
			} catch (e:Dynamic) {}
		}
		return isVideo(o) ? cast o : null;
	}

	public static function make(funk:Dynamic, tag:String, video:String, ?ext:String = 'mp4', ?x:Float = 0, ?y:Float = 0, ?loop:Dynamic = false):Void {
		tag = tag.replace('.', '');
		LuaUtils.destroyObject(tag);

		var path:String = Paths.video(video, ext == null ? 'mp4' : ext);
		if (!Assets.exists(path)) {
			LuaShared.luaTrace('makeVideoSprite: Couldnt find video: ' + video, false, false, FlxColor.RED);
			return;
		}

		var vid:FlxVideoSprite = new FlxVideoSprite(x, y);
		vid.antialiasing = true;
		try Reflect.setProperty(vid, 'autoPause', false) catch (e:Dynamic) {}
		vid.scrollFactor.set(0, 0);
		vid.cameras = [LuaShaders.safeCam(funk, 'camOther')];

		var ok:Bool = false;
		try {
			var localPath:String = Assets.getPath(path);
			ok = (loop == true) ? vid.load(localPath, [':input-repeat=65535']) : vid.load(localPath);
		} catch (e:Dynamic) {
			LuaShared.luaTrace('makeVideoSprite: error loading: ' + Std.string(e), false, false, FlxColor.RED);
		}
		if (!ok) {
			LuaShared.luaTrace('makeVideoSprite: could not load ' + video, false, false, FlxColor.RED);
			vid.destroy();
			return;
		}
		vid.setPosition(x, y);
		LuaShared.variables.set(tag, vid);
	}

	public static function setSize(funk:Dynamic, tag:String, x:Int, ?y:Int = 0, ?updateHitbox:Bool = true):Void {
		var vid:FlxVideoSprite = get(funk, tag);
		if (vid == null) {
			LuaShared.luaTrace('setVideoSize: Couldnt find video: ' + tag, false, false, FlxColor.RED);
			return;
		}
		var apply = function() {
			vid.setGraphicSize(x, y);
			if (updateHitbox) vid.updateHitbox();
		};
		var playing:Bool = false;
		try playing = vid.bitmap.isPlaying == true catch (e:Dynamic) {}
		if (!playing) try vid.bitmap.onFormatSetup.add(apply) catch (e:Dynamic) {}
		apply();
	}

	public static function addToState(funk:Dynamic, tag:String, ?front:Bool = false):Bool {
		var vid:FlxVideoSprite = get(funk, tag);
		if (vid == null) return false;

		var instance:Dynamic = LuaUtils.getTargetInstance();
		if (front) {
			instance.add(vid);
			return true;
		}
		var idx:Int = LuaProps.lowestCharacterIndex(funk, instance);
		if (idx < 0) instance.add(vid);
		else instance.insert(idx, vid);
		return true;
	}

	public static function remove(funk:Dynamic, tag:String, ?destroy:Bool = true, ?group:String = null):Void {
		var vid:FlxVideoSprite = get(funk, tag);
		if (vid == null) return;

		var groupObj:Dynamic = group == null ? LuaUtils.getTargetInstance() : LuaProps.resolveObject(funk, group);
		if (groupObj != null) groupObj.remove(vid, true);
		if (destroy) {
			LuaShared.variables.remove(tag);
			vid.destroy();
		}
	}

	public static function play(funk:Dynamic, tag:String):Void {
		var vid:FlxVideoSprite = get(funk, tag);
		if (vid == null) { LuaShared.luaTrace('playVideo: Couldnt find video: ' + tag, false, false, FlxColor.RED); return; }
		var playing:Bool = false;
		try playing = vid.bitmap.isPlaying == true catch (e:Dynamic) {}
		if (!playing) vid.play();
	}

	public static function resume(funk:Dynamic, tag:String):Void {
		var vid:FlxVideoSprite = get(funk, tag);
		if (vid == null) { LuaShared.luaTrace('resumeVideo: Couldnt find video: ' + tag, false, false, FlxColor.RED); return; }
		var playing:Bool = false;
		try playing = vid.bitmap.isPlaying == true catch (e:Dynamic) {}
		if (!playing) vid.resume();
	}

	public static function pause(funk:Dynamic, tag:String):Void {
		var vid:FlxVideoSprite = get(funk, tag);
		if (vid == null) { LuaShared.luaTrace('pauseVideo: Couldnt find video: ' + tag, false, false, FlxColor.RED); return; }
		var playing:Bool = false;
		try playing = vid.bitmap.isPlaying == true catch (e:Dynamic) {}
		if (playing) vid.pause();
	}

	public static function exists(funk:Dynamic, tag:String):Bool {
		return get(funk, tag) != null;
	}
}
