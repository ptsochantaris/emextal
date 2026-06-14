//
//  TokenizerLoader.swift
//  EmextalAudio
//
//  Provides a `TokenizerLoader` that bridges swift-tokenizers' `Tokenizer` to
//  `MLXLMCommon.Tokenizer`.
//
//  This intentionally replaces the `swift-tokenizers-mlx` integration package:
//  its published versions do not compile against `ml-explore/mlx-swift-lm` +
//  `swift-tokenizers` 0.7.x, because ml-explore's `MLXLMCommon.Tokenizer`
//  requires non-throwing `encode`/`decode`, while swift-tokenizers 0.7.x made
//  those calls typed-throwing — and the package's bridge calls them without
//  `try`. We perform the throwing → non-throwing adaptation here instead.
//

import Foundation
import MLXLMCommon
import Tokenizers

/// A `TokenizerLoader` that loads a tokenizer from a local model directory using
/// swift-tokenizers' Rust-backed `AutoTokenizer`.
public struct EmextalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    public init() {}

    public func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(directory: directory)
        return BridgedTokenizer(upstream)
    }
}

/// Adapts swift-tokenizers' typed-throwing `Tokenizers.Tokenizer` to the
/// non-throwing `MLXLMCommon.Tokenizer` protocol.
private struct BridgedTokenizer: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    // `MLXLMCommon.Tokenizer.encode`/`decode` are non-throwing, so encoding or
    // decoding failures are surfaced as empty results.
    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        (try? upstream.encode(text: text, addSpecialTokens: addSpecialTokens)) ?? []
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        (try? upstream.decode(tokenIds: tokenIds, skipSpecialTokens: skipSpecialTokens)) ?? ""
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
