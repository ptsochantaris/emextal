//
//  TokenizerLoader.swift
//  EmextalAudio
//
//  Provides a `TokenizerLoader` that bridges swift-tokenizers' `Tokenizer` to
//  `MLXLMCommon.Tokenizer`.
//
//  This intentionally replaces the `swift-tokenizers-mlx` integration package,
//  whose published versions don't track the `swift-tokenizers` API. The only
//  real adaptation left is the `decode(tokens:)` → `decode(tokenIds:)` label
//  and mapping the "missing chat template" error to its MLXLMCommon twin.
//

import Foundation
import MLXLMCommon
import Tokenizers

/// A `TokenizerLoader` that loads a tokenizer from a local model directory using
/// swift-tokenizers' Rust-backed `AutoTokenizer`.
public struct EmextalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    public init() {}

    public func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return BridgedTokenizer(upstream)
    }
}

/// Adapts swift-tokenizers' `Tokenizers.Tokenizer` to the `MLXLMCommon.Tokenizer` protocol.
private struct BridgedTokenizer: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch {
            // Map the upstream "no chat template" error to the MLXLMCommon
            // equivalent so callers can fall back to a default template. The
            // pattern is matched here (rather than in the `catch` clause) to
            // avoid a SILGen compiler crash with typed-throws pattern catches.
            if case Tokenizers.TokenizerError.missingChatTemplate = error {
                throw MLXLMCommon.TokenizerError.missingChatTemplate
            }
            throw error
        }
    }
}
