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
        let (leftB64, rightB64, diffB64) = try await Task.detached {
            let l = try Self.encodeImageToBase64(left, maxBytes: 1_000_000)
            let r = try Self.encodeImageToBase64(right, maxBytes: 1_000_000)
            let d = try Self.encodeImageToBase64(diff, maxBytes: 1_000_000)
            return (l, r, d)
        }.value

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

    func inspect(
        image: NSImage, metadata: PDFMetadata, pageMetadata: PDFPageMetadata
    ) async throws -> InspectionResult {
        let imageB64 = try await Task.detached {
            try Self.encodeImageToBase64(image, maxBytes: 1_000_000)
        }.value
        let contextText = Self.buildInspectionContext(metadata: metadata, pageMetadata: pageMetadata)
        let requestBody = Self.buildInspectionRequestBody(model: model, imageB64: imageB64, contextText: contextText)

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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIAnalysisError.invalidResponse("Could not extract content from response")
        }

        let cleanedContent = Self.extractJSON(from: content)
        guard let contentData = cleanedContent.data(using: .utf8) else {
            throw AIAnalysisError.invalidResponse("Content not valid UTF-8")
        }

        return try Self.parseInspectionResponse(contentData)
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

    static func buildInspectionContext(metadata: PDFMetadata, pageMetadata: PDFPageMetadata) -> String {
        var parts: [String] = []
        parts.append("--- DOCUMENT METADATA ---")
        parts.append("PDF Version: \(metadata.pdfVersion)")
        parts.append("Pages: \(metadata.pageCount)")
        parts.append("File size: \(metadata.fileSizeBytes) bytes")
        parts.append("Encrypted: \(metadata.isEncrypted)")
        if !metadata.colorProfiles.isEmpty {
            parts.append("Color profiles: \(metadata.colorProfiles.joined(separator: ", "))")
        }
        parts.append("--- PAGE 1 ---")
        parts.append("Size: \(pageMetadata.widthPt)pt x \(pageMetadata.heightPt)pt")
        parts.append("Rotation: \(pageMetadata.rotation)°")
        if !pageMetadata.fontNames.isEmpty {
            parts.append("Fonts: \(pageMetadata.fontNames.joined(separator: ", "))")
        }
        parts.append("Images: \(pageMetadata.imageCount)")
        return parts.joined(separator: "\n")
    }

    static func buildInspectionRequestBody(model: String, imageB64: String, contextText: String) -> [String: Any] {
        let systemPrompt = """
        You are an expert prepress QC inspector and packaging compliance analyst. You inspect a single PDF artwork page for print-readiness and regulatory compliance issues.

        You will receive one image: a rendered PDF page. You will also receive document metadata (fonts, color profiles, page dimensions).

        Respond with valid JSON only (no markdown, no code fences) with exactly these keys:

        {
            "issues": [
                {
                    "id": 1,
                    "severity": "pass|warn|fail",
                    "category": "category_name",
                    "title": "Short title",
                    "detail": "Full explanation of the issue",
                    "location": {"x": 0.0, "y": 0.0, "w": 1.0, "h": 0.1} or null
                }
            ],
            "summary": "One-paragraph overall assessment"
        }

        Location coordinates are percentages (0.0 to 1.0) relative to the page:
        - x: distance from left edge
        - y: distance from top edge
        - w: width as fraction of page width
        - h: height as fraction of page height
        Set location to null for page-wide issues (e.g., wrong color space).

        Valid categories: bleed, resolution, colorSpace, fontEmbedding, overprint, transparency, barcodeUPC, requiredText, nutritionPanel, allergenWarning, recyclingSymbols, countryOfOrigin, legalDisclaimers

        Evaluate ALL of these checks:

        PREPRESS QC:
        - Bleed/trim safety: Does artwork extend beyond the visible content area? Are critical elements too close to edges?
        - Image resolution: Do images appear sharp at print size, or pixelated/low-res?
        - Color space: Based on color profiles metadata, is the document CMYK-ready or still RGB?
        - Font embedding: Are fonts listed in metadata standard print fonts? Any potential embedding issues?
        - Overprint/knockout: Any visible overprint artifacts or misregistration signs?
        - Transparency: Any visible transparency flattening issues?

        PACKAGING REGULATORY:
        - Required text: Are mandatory text elements present and legible (ingredient lists, warnings, etc.)?
        - Barcode/UPC: Is a barcode present? Does it appear intact and scannable?
        - Nutrition panel: If a nutrition facts panel is present, is it properly formatted?
        - Allergen warnings: Are allergen declarations visible and prominent?
        - Recycling symbols: Are recycling/disposal symbols present?
        - Country of origin: Is country of origin text present?
        - Legal disclaimers: Are trademark symbols (R), (TM) and required legal text present?

        For each check, report severity:
        - "pass": Check passes, no issues
        - "warn": Minor concern or could not fully verify
        - "fail": Clear issue that needs attention

        Include all checks in the issues array, even passing ones. Be specific about what you see.
        """

        return [
            "model": model,
            "temperature": 0,
            "max_tokens": 3000,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": "Inspect this PDF artwork page for prepress and packaging compliance issues:"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageB64)", "detail": "high"]],
                    ["type": "text", "text": contextText],
                ]],
            ],
        ]
    }

    func generateNarrative(
        preflight: SwiftPreflightResult,
        barcodes: [DetectedBarcode],
        inspection: InspectionResult?
    ) async throws -> String {
        var context = "Preflight: \(preflight.summary.passCount) pass, \(preflight.summary.warnCount) warn, \(preflight.summary.failCount) fail."
        if !barcodes.isEmpty {
            context += " Barcodes: \(barcodes.map { "\($0.displaySymbology): \($0.payload)" }.joined(separator: ", "))."
        }
        if let inspection = inspection {
            context += " AI Inspection: \(inspection.summary)"
        }

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "max_tokens": 500,
            "messages": [
                ["role": "system", "content": "You are a prepress QC specialist. Write a concise 2-3 sentence plain-language summary of the QC findings suitable for client communication. Be factual and professional."],
                ["role": "user", "content": context],
            ],
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return message?["content"] as? String ?? "Unable to generate narrative."
    }
}
