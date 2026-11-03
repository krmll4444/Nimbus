import SwiftUI

/// In-app legal page with an explicit Back control.
/// Renders markdown as spaced plain text (SwiftUI `AttributedString(markdown:)` collapses newlines).
struct LegalDocumentView: View {
    let document: LegalDocuments
    @ObservedObject var settings: AppSettings
    var onBack: () -> Void

    @State private var hoveringBack = false

    private var bodyText: String {
        Self.readableText(from: LegalDocuments.loadText(document))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Text(bodyText)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(settings.t(.back))
                        .font(.body)
                }
                .foregroundStyle(hoveringBack ? Color.accentColor : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hoveringBack ? 0.08 : 0))
                )
            }
            .buttonStyle(.plain)
            .onHover { hoveringBack = $0 }
            .help(settings.t(.back))

            Spacer(minLength: 8)

            Text(document.title(using: settings))
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(AppVersion.displayString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Convert markdown into readable plain text with real paragraphs and blank lines.
    static func readableText(from markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var out: [String] = []
        var inCode = false
        var skipTitle = true

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                inCode.toggle()
                if inCode {
                    out.append("")
                } else {
                    out.append("")
                }
                continue
            }

            if inCode {
                out.append(raw) // keep indentation inside fences
                continue
            }

            if line.isEmpty {
                if out.last != "" { out.append("") }
                continue
            }

            if skipTitle, line.hasPrefix("# ") {
                skipTitle = false
                continue
            }
            skipTitle = false

            if line.hasPrefix("## ") {
                if out.last != "" { out.append("") }
                out.append(String(line.dropFirst(3)))
                out.append("")
                continue
            }

            if line.hasPrefix("### ") {
                if out.last != "" { out.append("") }
                out.append(String(line.dropFirst(4)))
                out.append("")
                continue
            }

            // Tables → "Cell — Cell"
            if line.hasPrefix("|") {
                let cells = line
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" || $0.isWhitespace } }) {
                    continue
                }
                out.append(cells.joined(separator: "  —  "))
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                out.append("•  " + stripInlineMarkup(String(line.dropFirst(2))))
                continue
            }

            if let numbered = numberedListItem(line) {
                out.append(numbered)
                continue
            }

            out.append(stripInlineMarkup(line))
        }

        // Collapse 3+ blank lines → 1 blank line between paragraphs.
        var cleaned: [String] = []
        for line in out {
            if line.isEmpty, cleaned.last?.isEmpty == true { continue }
            cleaned.append(line)
        }
        return cleaned.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func numberedListItem(_ line: String) -> String? {
        // "1. Item" / "12. Item"
        guard let dot = line.firstIndex(of: "."),
              dot > line.startIndex,
              line[line.startIndex..<dot].allSatisfy(\.isNumber)
        else { return nil }
        let restStart = line.index(after: dot)
        guard restStart < line.endIndex, line[restStart] == " " else { return nil }
        let number = line[line.startIndex..<dot]
        let body = stripInlineMarkup(String(line[line.index(after: restStart)...]))
        return "\(number).  \(body)"
    }

    private static func stripInlineMarkup(_ text: String) -> String {
        var result = text
        // **bold** / __bold__
        while let start = result.range(of: "**") {
            if let end = result.range(of: "**", range: start.upperBound..<result.endIndex) {
                let inner = result[start.upperBound..<end.lowerBound]
                result.replaceSubrange(start.lowerBound..<end.upperBound, with: inner)
            } else { break }
        }
        // `code`
        result = result.replacingOccurrences(of: "`", with: "")
        return result
    }
}
