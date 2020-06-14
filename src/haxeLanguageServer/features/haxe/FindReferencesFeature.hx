package haxeLanguageServer.features.haxe;

import haxe.display.Display.DisplayMethods;
import haxeLanguageServer.helper.HaxePosition;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class FindReferencesFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(ReferencesRequest.type, onFindReferences);
	}

	function onFindReferences(params:TextDocumentPositionParams, token:CancellationToken, resolve:Array<Location>->Void, reject:ResponseError<NoData>->Void) {
		var uri = params.textDocument.uri;
		var doc = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}
		var handle = if (context.haxeServer.supports(DisplayMethods.FindReferences)) handleJsonRpc else handleLegacy;
		handle(params, token, resolve, reject, doc, doc.offsetAt(params.position));
	}

	function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void, reject:ResponseError<NoData>->Void,
			doc:TextDocument, offset:Int) {
		context.callHaxeMethod(DisplayMethods.FindReferences, {
			file: doc.uri.toFsPath(),
			contents: doc.content,
			offset: offset,
			kind: WithBaseAndDescendants
		}, token, locations -> {
			resolve(locations.filter(location -> location != null).map(location -> {
				{
					uri: location.file.toUri(),
					range: location.range
				}
			}));
			return null;
		}, reject.handler());
	}

	function handleLegacy(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void, reject:ResponseError<NoData>->Void,
			doc:TextDocument, offset:Int) {
		var bytePos = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position));
		var args = ['${doc.uri.toFsPath()}@$bytePos@usage'];
		context.callDisplay("@usage", args, doc.content, token, function(r) {
			switch r {
				case DCancelled:
					resolve(null);
				case DResult(data):
					var xml = try Xml.parse(data).firstElement() catch (_:Any) null;
					if (xml == null)
						return reject.invalidXml(data);

					var positions = [for (el in xml.elements()) el.firstChild().nodeValue];
					if (positions.length == 0)
						return resolve([]);

					var results = [];
					var haxePosCache = new Map();
					for (pos in positions) {
						var location = HaxePosition.parse(pos, doc, haxePosCache, context.displayOffsetConverter);
						if (location == null) {
							trace("Got invalid position: " + pos);
							continue;
						}
						results.push(location);
					}

					resolve(results);
			}
		}, reject.handler());
	}
}