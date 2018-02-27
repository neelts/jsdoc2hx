package ;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;

using StringTools;
using JSDoc2HX;

class JSDoc2HX {

	private static inline var JSON_EXT:String = '.json';
	private static inline var JS_HTML:String = 'js.html.';

	private static var replaces = {
		'HTMLCanvasElement': JS_HTML + 'CanvasElement',
		'CanvasRenderingContext2D': JS_HTML,
		'Float32Array': JS_HTML,
		'Uint32Array': JS_HTML
	};

	private static var out:String = 'out';

	public static function main():Void {
		for (arg in Sys.args()) if (arg.isJSONExt()) loadJSON(arg);
	}

	private static function loadJSON(jsonFile:String):Void {
		if (FileSystem.exists(jsonFile)) {
			var json:String = null;
			try {
				json = Json.parse(File.getContent(jsonFile));
			} catch (e:String) {
				trace(e);
			}
			if (json != null) processJSON(cast json);
		} else {
			trace('File $jsonFile not exists!');
		}
	}

	private static var classes:Map<String, HXClass> = new Map<String, HXClass>();

	private static function processJSON(json:JSDocs):Void {

		for (doc in json.docs) {
			if (doc.memberof != null) {
				var long:Array<String> = Std.string(
					doc.longname.indexOf('#') != -1 ? doc.longname.substring(0, doc.longname.indexOf('#')) : doc.longname
				).split('.');
				if (doc.kind == JSDocKind.Member) long.pop();
				var longPath:String = long.join('.');
				var hxClass:HXClass = classes.get(longPath);
				if (hxClass == null) classes.set(longPath, hxClass = {});
				var kinds:Array<JSDoc> = Reflect.field(hxClass, '_${doc.kind}');
				if (kinds == null) Reflect.setField(hxClass, '_${doc.kind}', kinds = []);
				kinds.push(doc);
			}
		}

		for (classPath in classes.keys()) {
			var hxClass:HXClass = classes.get(classPath);
			var path:Array<String> = classPath.convertPackages();
			var className:String = path.last().capital();
			var content:String = '';
			content += 'package ${ path.head().join('.') };\n';
			content += '@:native("$classPath")\n';
			content += 'extern class $className {\n';
			if (hxClass._member.isNotEmpty()) content += getMembers(hxClass._member);
			content += '}';
			var packagePath:String = path.head().join('/');
			if (!FileSystem.exists('$out/$packagePath')) FileSystem.createDirectory('$out/$packagePath');
			File.saveContent('$out/$packagePath/$className.hx', content);
		}
	}

	private static function getMembers(members:Array<JSDoc>):String {
		members.sort(function(a:JSDoc, b:JSDoc) {
			return a.scope == b.scope ? (
				a.access == b.access ? (a.name > b.name ? 1 : -1) : (Std.string(a.access) > Std.string(b.access) ? 1 : -1)
			) : ((a.scope != JSDocScope.Static && b.scope == JSDocScope.Static) ? 1 : -1);
		});
		var result:String = '\n';
		var firstMember:JSDoc = members.first();
		var lastScope:JSDocScope = firstMember.scope;
		var lastAccess:JSDocAccess = firstMember.access;
		var memberMap:Map<String, Bool> = new Map<String, Bool>();
		for (member in members) {
			if (memberMap.exists(member.name)) continue;
			if (lastScope != member.scope || lastAccess != member.access) {
				lastScope = member.scope;
				lastAccess = member.access;
				result += '\n';
			}
			result += '\t${ getAccess(member) }${ getScope(member) } var ${ member.name }:${ getTypes(member) };\n';
			memberMap.set(member.name, true);
		}
		result += '\n';
		return result;
	}

	private static function getTypes(doc:JSDoc):String {
		var typeNames:JSDocTypeNames = doc.type;
		var c:String = doc.comment;
		if (typeNames != null && typeNames.names.isNotEmpty()) {
			var names:Array<JSDocType> = typeNames.names;
			return switch (names.length) {
				case 1: getType(names.last(), c);
				case 2: 'haxe.extern.EitherType<${ getType(names.first(), c)},${ getType(names.last(), c) }>';
				default: getType(JSDocType.Any);
			}
		} else return getType(JSDocType.Any);
	}

	private static function getType(type:JSDocType, ?c:String):String {
		return switch(type) {
			case JSDocType.Number, JSDocType.Float: 'Float';
			case JSDocType.Integer: 'Int';
			case JSDocType.String: 'String';
			case JSDocType.Boolean: 'Bool';
			case JSDocType.Array: 'Array<Any>';
			case JSDocType.Function: 'Void->Void';
			case JSDocType.Any, JSDocType.Object, JSDocType.Null: 'Any';
			case JSDocType.ObjectDef: {
				var type:String = '@type ';
				var typeIndex:Int = c.indexOf(type) + type.length;
				var t:String = c.substring(typeIndex, c.indexOf('\r', typeIndex));
				var pairs:Array<String> = t.substring(1, t.length - 1).replace(' ', '').split(',');
				var result:String = '{';
				for (pair in pairs) {
					var keyValue:Array<String> = pair.split(':');
					result += ' ${ keyValue.first() }:${ getType(keyValue.last()) } ';
				}
				trace(result + '}');
				result + '}';
			}
			default: {
				var t:String = Std.string(type);
				if (t.indexOf('Array.<') == 0) {
					'Array<${ t.substring(t.indexOf('<') + 1, t.indexOf('>')).convertPackages().join('.') }>';
				} else checkReplace(t.convertPackages().join('.'));
			}
		}
	}

	private static function checkReplace(type:String):String {
		return if (Reflect.hasField(replaces, type)) {
			var replace:String = Reflect.field(replaces, type);
			if (replace.charAt(replace.length - 1) == '.') replace + type else replace;  
		} else type;
	}

	private static function getAccess(doc:JSDoc):String {
		return switch (doc.access) {
			case JSDocAccess.Private: 'private';
			case JSDocAccess.Protected: '@:protected';
			default: 'public';
		}
	}

	private static function getScope(doc:JSDoc):String {
		return switch (doc.scope) {
			case JSDocScope.Static: ' static';
			default: '';
		}
	}

	public static inline function isJSONExt(filePath:String):Bool {
		return filePath.length > JSON_EXT.length && filePath.substr(-JSON_EXT.length) == JSON_EXT;
	}

	public static inline function capital(string:String):String return string.substring(0, 1).toUpperCase() + string.substring(1);

	public static inline function first<T>(array:Array<T>):T return array[0];

	public static inline function last<T>(array:Array<T>):T return array[array.length - 1];

	public static inline function head<T>(array:Array<T>):Array<T> return array.slice(0, array.length - 1);

	public static inline function isNotEmpty<T>(array:Array<T>):Bool return array != null && array.length > 0;

	public static inline function convertPackages(classPath:String):Array<String> {
		var path:Array<String> = classPath.split('.');
		for (i in 0...path.length - 1) path[i] = path[i].substr(0, 1).toLowerCase() + path[i].substr(1);
		return path;
	}
}

typedef HXClass = {
	@:optional var _class:Array<JSDoc>;
	@:optional var _member:Array<JSDoc>;
	@:optional var _function:Array<JSDoc>;
	@:optional var _event:Array<JSDoc>;
	@:optional var _typedef:Array<JSDoc>;
	@:optional var _namespace:Array<JSDoc>;
}

@:enum abstract JSDocKind(String) {
	var Class = 'class';
	var Function = 'function';
	var Member = 'member';
	var Event = 'event';
	var TypeDef = 'typedef';
	var NameSpace = 'namespace';
}

@:enum abstract JSDocAccess(String) {
	var Public = 'public';
	var Private = 'private';
	var Protected = 'protected';
}

@:enum abstract JSDocScope(String) {
	var Static = 'static';
	var Global = 'global';
	var Instance = 'instance';
}

@:enum abstract JSDocType(String) from String {
	var Number = 'number';
	var Float = 'float';
	var Integer = 'integer';
	var String = 'string';
	var Boolean = 'boolean';
	var Array = 'array';
	var Function = 'function';
	var Null = 'null';
	var Any = 'any';
	var Object = 'object';
	var ObjectDef = 'Object';
}

typedef JSDocs = {
	var docs:Array<JSDoc>;
}

typedef JSDoc = {
	var comment:String;
	var meta:JSDocMeta;
	var kind:JSDocKind;
	var name:String;
	@:optional var type:JSDocTypeNames;
	@:optional var access:JSDocAccess;
	@:optional var params:Array<JSDocParam>;
	@:optional var returns:Array<JSDocReturn>;
	var memberof:String;
	var longname:String;
	var scope:JSDocScope;
}

typedef JSDocMeta = {
	var filename:String;
}

typedef JSDocParam = {
	var type:JSDocTypeNames;
	var description:String;
	var name:String;
	@:optional var optional:Bool;
	@:optional var defaultvalue:Any;
}

typedef JSDocTypeNames = {
	var names:Array<JSDocType>;
}

typedef JSDocReturn = {
	var type:JSDocTypeNames;
	var description:String;
}