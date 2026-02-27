import Foundation
import AppKit

enum AIAnalysisError: Error, LocalizedError {
    case invalidAPIKey
    case rateLimited
    case networkError(String)
    case invalidResponse(String)
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: "Invalid API key — check Settings"
        case .rateLimited: "Rate limited — try again in a moment"
        case .networkError(let msg): "Network error: \(msg)"
        case .invalidResponse(let msg): "Invalid response: \(msg)"
        case .imageEncodingFailed: "Failed to encode image"
        }
    }
}

final class OpenRouterAIService: AIAnalysisServiceProtocol, @unchecked Sendable {
    private let apiKey: String
    private let model = "google/gemini-2.5-flash"
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func analyze(
        left: NSImage, right: NSImage, diff: NSImage,
        leftText: String, rightText: String,
        diffResult: PDFDiffResult,
        structuralDiff: PDFStructuralDiffResult
    ) async throws -> AIAnalysisResult {
        let leftB64 = try Self.encodeImageToBase64(left, maxBytes: 1_000_000)
        let rightB64 = try Self.encodeImageToBase64(right, maxBytes: 1_000_000)
        let diffB64 = try Self.encodeImageToBase64(diff, maxBytes: 1_000_000)

        let contextText = Self.buildContextText(
            leftText: leftText, rightText: rightText,
            diffResult: diffResult, structuralDiff: structuralDiff
        )

        let requestBody = Self.buildRequestBody(
            model: model,
            leftB64: leftB64, rightB64: rightB64, diffB64: diffB64,
            contextText: contextText
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("PDF Diff Desktop", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIAnalysisError.networkError("No HTTP response")
        }

        switch http.statusCode {
        case 200: break
        case 401: throw AIAnalysisError.invalidAPIKey
        case 429: throw AIAnalysisError.rateLimited
        default: throw AIAnalysisError.networkError("HTTP \(http.statusCode)")
        }

        // Extract content from OpenRouter response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIAnalysisError.invalidResponse("Could not extract content from response")
        }

        // Try to parse as JSON, extracting from markdown code fence if needed
        let cleanedContent = Self.extractJSON(from: content)
        guard let contentData = cleanedContent.data(using: .utf8) else {
            throw AIAnalysisError.invalidResponse("Content not valid UTF-8")
        }

        do {
            return try Self.parseAnalysisResponse(contentData)
        } catch {
            // Fallback: treat the raw text as visual changes
            return AIAnalysisResult(
                visualChanges: content,
                textComparison: "",
                qcChecklist: [],
                anomalies: ""
            )
        }
    }

    // MARK: - Static Helpers (testable)

    static func encodeImageToBase64(_ image: NSImage, maxBytes: Int) throws -> String {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            throw AIAnalysisError.imageEncodingFailed
        }

        // Try quality 0.8 first, reduce to 0.6 if too large
        var quality: Double = 0.8
        var data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])

        if let d = data, d.count > maxBytes {
            quality = 0.6
            data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }

        guard let jpegData = data else {
            throw AIAnalysisError.imageEncodingFailed
        }

        return jpegData.base64EncodedString()
    }

    static func parseAnalysisResponse(_ data: Data) throws -> AIAnalysisResult {
        struct RawResponse: Decodable {
            let visual_changes: String?
            let text_comparison: String?
            let qc_checklist: [QCCheckItem]?
            let anomalies: String?
        }

        let raw = try JSONDecoder().decode(RawResponse.self, from: data)
        return AIAnalysisResult(
            visualChanges: raw.visual_changes ?? "",
            textComparison: raw.text_comparison ?? "",
            qcChecklist: raw.qc_checklist ?? [],
            anomalies: raw.anomalies ?? ""
        )
    }

    static func extractJSON(from content: String) -> String {
        // Strip markdown code fences if present
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            let stripped = lines.dropFirst().dropLast().joined(separator: "\n")
            return stripped
        }
        return trimmed
    }

    static func parseInspectionResponse(_ data: Data) throws -> InspectionResult {
        struct RawLocation: Decodable {
            let x: Double
            let y: Double
            let w: Double
            let h: Double
        }

        struct RawIssue: Decodable {
            let id: Int
            let severity: String
            let category: String
            let title: String
            let detail: String
            let location: RawLocation?
        }

        struct RawInspectionResponse: Decodable {
            let issues: [RawIssue]
            let summary: String
        }

        let raw = try JSONDecoder().decode(RawInspectionResponse.self, from: data)

        let issues = raw.issues.map { rawIssue in
            InspectionIssue(
                id: rawIssue.id,
                severity: IssueSeverity(rawValue: rawIssue.severity) ?? .warn,
                category: IssueCategory(rawValue: rawIssue.category) ?? .requiredText,
                title: rawIssue.title,
                detail: rawIssue.detail,
                location: rawIssue.location.map {
                    IssueLocation(x: $0.x, y: $0.y, w: $0.w, h: $0.h)
                }
            )
        }

        return InspectionResult(issues: issues, summary: raw.summary)
    }

    static func buildContextText(
        leftText: String, rightText: String,
        diffResult: PDFDiffResult,
        structuralDiff: PDFStructuralDiffResult
    ) -> String {
        var parts: [String] = []

        parts.append("--- LEFT PAGE TEXT ---\n\(leftText.prefix(3000))")
        parts.append("--- RIGHT PAGE TEXT ---\n\(rightText.prefix(3000))")
        parts.append("--- DIFF SUMMARY ---")
        parts.append("Similarity: \(String(format: "%.2f%%", diffResult.similarityScore * 100))")
        parts.append("Changed pixels: \(diffResult.changedPixelCount) / \(diffResult.totalPixelCount)")
        parts.append("Changed regions: \(diffResult.changedRegions.count)")

        if !structuralDiff.metadataChanges.isEmpty {
            parts.append("Metadata changes: \(structuralDiff.metadataChanges.count)")
        }
        if !structuralDiff.textChanges.isEmpty {
            parts.append("Text changes on \(structuralDiff.textChanges.count) page(s)")
        }
        if !structuralDiff.pageSizeChanges.isEmpty {
            parts.append("Page size changes: \(structuralDiff.pageSizeChanges.count)")
        }

        return parts.joined(separator: "\n")
    }

    static func buildRequestBody(
        model: String,
        leftB64: String, rightB64: String, diffB64: String,
        contextText: String
    ) -> [String: Any] {
        let systemPrompt = """
        You are an expert prepress and print QC analyst. You analyze PDF page comparisons and provide structured feedback.

        You will receive three images:
        1. Left (original) page render
        2. Right (revised) page render
        3. Diff bitmap highlighting pixel-level changes in red

        You will also receive extracted text from both pages and a structured diff summary.

        Respond with valid JSON only (no markdown, no code fences) with exactly these keys:

        {
            "visual_changes": "Natural language description of all visual differences you can see between the two pages. Be specific about positions, sizes, colors.",
            "text_comparison": "Semantic summary of text content changes. Describe what was added, removed, or reworded and why it matters.",
            "qc_checklist": [
                {"check": "Check name", "status": "pass|warn|fail", "detail": "Explanation"}
            ],
            "anomalies": "Any unexpected, suspicious, or critical findings that warrant special attention."
        }

        For qc_checklist, evaluate these checks:
        - Bleed/trim safety: Are important elements too close to page edges?
        - Text readability: Is any text too small, overlapping, or poorly positioned?
        - Barcode/QR integrity: Are barcodes or QR codes intact and unchanged (if present)?
        - Color consistency: Are colors consistent between versions?
        - Image quality: Do images appear sharp and properly placed?
        - Font rendering: Do fonts appear consistent and properly rendered?
        - Alignment/registration: Are elements properly aligned between versions?
        - Unintended changes: Are there any changes that look accidental?

        If a section has nothing to report, say "No issues found" for that section.
        For qc_checklist, if a check is not applicable (e.g., no barcodes present), use status "pass" with detail "Not applicable".
        """

        return [
            "model": model,
            "temperature": 0,
            "max_tokens": 2000,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": "Analyze these two PDF pages and their differences:"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(leftB64)", "detail": "high"]],
                    ["type": "text", "text": "Left (original) page above. Right (revised) page below:"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(rightB64)", "detail": "high"]],
                    ["type": "text", "text": "Diff bitmap (changes highlighted in red):"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(diffB64)", "detail": "high"]],
                    ["type": "text", "text": contextText],
                ]],
            ],
        ]
    }
}
