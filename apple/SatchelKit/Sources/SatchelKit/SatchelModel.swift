import Foundation
import JavaScriptCore
import Synchronization

/// URL normalization, item IDs, and merge rules, computed by `@satchel/model` itself running in JavaScriptCore
/// (ADR-0020), so every client agrees on identity and merges. Load `model.jsc.iife.js` (staged in
/// `apple/Staged/web/`), not the browser bundle: bare JavaScriptCore has no `URL` or `TextEncoder`.
///
/// The context is created on first use and reused. Calls are serialized; each takes well under a millisecond once
/// the context exists.
public final class SatchelModel: Sendable {
    /// Name of the bundled script resource in the app and extension bundles.
    public static let resourceName = "model.jsc.iife"

    private let source: String
    private let state = Mutex<State?>(nil)

    public init(source: String) {
        self.source = source
    }

    /// The model bundled with the app or extension.
    public static func bundled(in bundle: Bundle = .main) throws(SatchelModelError) -> SatchelModel {
        guard let url = bundle.url(forResource: resourceName, withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { throw .missingScript }
        return SatchelModel(source: source)
    }

    /// §7.2: the canonical URL when it is on the same site as the page, otherwise the page URL, normalized.
    public func normalizedURL(pageURL: String, canonicalURL: String? = nil) throws(SatchelModelError) -> String {
        try call("normalizedUrlFor", pageURL, canonicalURL)
    }

    /// `"u_"` + the first 32 hex characters of SHA-256 over the normalized URL.
    public func itemID(forNormalizedURL normalizedURL: String) throws(SatchelModelError) -> String {
        try call("itemIdFor", normalizedURL)
    }

    /// §7.3, for a re-save of the same ID or a sync conflict. Pure and commutative.
    public func merge(_ a: Item, _ b: Item) throws(SatchelModelError) -> MergeResult {
        let encoder = JSONEncoder()
        let json: String
        do {
            json = try String(
                decoding: encoder.encode([a, b]), as: UTF8.self)
        } catch {
            throw .script("could not encode items: \(error)")
        }
        let result: String = try call("__mergeJSON", json)
        do {
            return try JSONDecoder().decode(MergeResult.self, from: Data(result.utf8))
        } catch {
            throw .script("could not decode the merge result: \(error)")
        }
    }

    // MARK: - JavaScriptCore

    private final class State {
        let context: JSContext
        let model: JSValue
        var exception: JSValue?

        init(context: JSContext, model: JSValue) {
            self.context = context
            self.model = model
        }
    }

    private static func makeState(source: String) throws(SatchelModelError) -> State {
        guard let context = JSContext() else { throw .script("could not create a JavaScript context") }
        var loadError: String?
        context.exceptionHandler = { _, exception in loadError = exception?.toString() }
        context.evaluateScript(source)
        // Items cross the bridge as JSON text, so neither side depends on JSValue's object conversion.
        context.evaluateScript(
            """
            SatchelModel.__mergeJSON = function (json) {
              var pair = JSON.parse(json);
              return JSON.stringify(SatchelModel.mergeItems(pair[0], pair[1]));
            };
            """)
        if let loadError { throw .script("the model script failed to load: \(loadError)") }
        guard let model = context.objectForKeyedSubscript("SatchelModel"), model.isObject else {
            throw .script("the script did not define globalThis.SatchelModel")
        }
        let state = State(context: context, model: model)
        context.exceptionHandler = { [unowned state] _, exception in state.exception = exception }
        return state
    }

    private func call(_ function: String, _ arguments: String?...) throws(SatchelModelError) -> String {
        let source = self.source
        let outcome: Result<String, SatchelModelError> = state.withLock { state in
            do throws(SatchelModelError) {
                let current: State
                if let existing = state {
                    current = existing
                } else {
                    current = try Self.makeState(source: source)
                    state = current
                }
                current.exception = nil
                let args: [Any] = arguments.map { $0 ?? JSValue(undefinedIn: current.context) as Any }
                let value = current.model.objectForKeyedSubscript(function)?.call(withArguments: args)
                if let exception = current.exception {
                    let name = exception.objectForKeyedSubscript("name")?.toString() ?? ""
                    let message = exception.objectForKeyedSubscript("message")?.toString() ?? exception.toString() ?? ""
                    if name == "UnsupportedUrlError" { return .failure(.unsupportedURL(message)) }
                    return .failure(.script("\(name): \(message)"))
                }
                guard let value, value.isString, let string = value.toString() else {
                    return .failure(.script("\(function) did not return a string"))
                }
                return .success(string)
            } catch {
                return .failure(error)
            }
        }
        return try outcome.get()
    }
}

public enum SatchelModelError: Error, Equatable {
    /// The bundle has no `model.jsc.iife.js`.
    case missingScript
    /// Only http and https URLs can be saved.
    case unsupportedURL(String)
    case script(String)
}

/// The result of `SatchelModel.merge`, matching `MergeResult` in `packages/model/src/merge.ts`.
public struct MergeResult: Codable, Sendable, Equatable {
    public enum BodyOwner: String, Codable, Sendable {
        case a, b, none
    }

    public var item: Item
    /// Whose Markdown body the merged item keeps.
    public var body: BodyOwner
    /// Both sides had a page body and one replaces the other: ask "Replace saved copy?" on an interactive re-save.
    public var replacesBody: Bool

    public init(item: Item, body: BodyOwner, replacesBody: Bool) {
        self.item = item
        self.body = body
        self.replacesBody = replacesBody
    }
}
