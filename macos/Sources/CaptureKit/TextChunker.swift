import Foundation

/// 把过长的段落按句子切成不超过 `limit` 字符的块（送上下文有限的端上大模型前用）。
/// 优先在句末标点/换行处切；单句就超长时才在空格或字符边界硬切。
public enum TextChunker {
    public static func split(_ text: String, limit: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit, limit > 0 else { return trimmed.isEmpty ? [] : [trimmed] }

        var chunks: [String] = []
        var current = ""
        for sentence in sentences(of: trimmed) {
            for piece in hardSplit(sentence, limit: limit) {
                if current.isEmpty {
                    current = piece
                } else if current.count + 1 + piece.count <= limit {
                    current += (current.last?.isCJK == true && piece.first?.isCJK == true) ? piece : " " + piece
                } else {
                    chunks.append(current)
                    current = piece
                }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// 按句末标点（。．！？!? 及换行）切句，标点留在句尾。
    static func sentences(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let terminators: Set<Character> = ["。", "．", "！", "？", "!", "?", "\n"]
        let characters = Array(text)
        for (index, ch) in characters.enumerated() {
            current.append(ch)
            let isPeriod = ch == "." && (index + 1 == characters.count || characters[index + 1].isWhitespace)
            if terminators.contains(ch) || isPeriod {
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { result.append(s) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    /// 单句超长：先在空格处切，没有空格就按字符数切。
    static func hardSplit(_ sentence: String, limit: Int) -> [String] {
        guard sentence.count > limit else { return [sentence] }
        var pieces: [String] = []
        var current = ""
        for word in sentence.split(separator: " ", omittingEmptySubsequences: true) {
            let w = String(word)
            if w.count > limit {
                if !current.isEmpty { pieces.append(current); current = "" }
                var rest = Substring(w)
                while rest.count > limit {
                    pieces.append(String(rest.prefix(limit)))
                    rest = rest.dropFirst(limit)
                }
                current = String(rest)
            } else if current.isEmpty {
                current = w
            } else if current.count + 1 + w.count <= limit {
                current += " " + w
            } else {
                pieces.append(current)
                current = w
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
