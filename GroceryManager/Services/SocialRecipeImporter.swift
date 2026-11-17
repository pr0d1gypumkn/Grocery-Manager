import Foundation
import Vision
import UIKit

/// Recipes from photos, screenshots and handwritten cards: on-device OCR with Vision,
/// then the same on-device language model that parses pasted notes. No network.
struct PhotoRecipeImporter {
    func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw RecipeImportError.noRecipeContent }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations: [RecognizedTextObservation] = try await request.perform(on: cgImage, orientation: Self.orientation(image.imageOrientation))
        let lines: [String] = observations.compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    static func orientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }

    func importRecipe(from image: UIImage) async throws -> ImportedRecipeDraft {
        let text = try await recognizeText(in: image)
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else { throw RecipeImportError.noRecipeContent }
        var draft = try await OnDeviceRecipeImporter().importRecipe(from: .note(text))
        draft.method = "photo"
        return draft
    }
}

/// Recipes from TikTok, Instagram and YouTube links. Strategy, in order:
/// 1. the page's own schema.org markup (some creators embed full recipes),
/// 2. the server's social endpoint (oEmbed metadata; partner APIs once keys exist),
/// 3. the page's description/caption text through the on-device model.
struct SocialRecipeImporter {
    private struct ServerResponse: Decodable {
        var platform: String
        var title: String
        var author: String?
        var description: String?
        var note: String
    }

    static func isSocialURL(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return host.contains("tiktok.com") || host.contains("instagram.com") || host.contains("youtube.com") || host == "youtu.be"
    }

    func importRecipe(from url: URL) async throws -> ImportedRecipeDraft {
        let html = (try? await HTMLFetcher.fetch(url)) ?? ""
        if !html.isEmpty, let parsed = RecipeSchemaParser.parse(html: html, sourceURL: url) {
            var draft = ImportedRecipeDraft(parsed: parsed, method: "social-schema")
            draft.sourceURL = url.absoluteString
            return draft
        }

        var caption = Self.caption(fromHTML: html)
        var title = ""
        if await AccountSession.shared.isSignedIn {
            if let response = try? await APIClient.shared.post("/api/import/social", body: ["url": url.absoluteString], as: ServerResponse.self) {
                title = response.title
                if let description = response.description, description.count > caption.count { caption = description }
            }
        }
        guard caption.count > 30 else {
            throw RecipeImportError.networkFailure("The post's caption couldn't be read. Paste the caption as a note, or import a screenshot instead.")
        }
        var draft = try await OnDeviceRecipeImporter().importRecipe(from: .note(title.isEmpty ? caption : "\(title)\n\n\(caption)"))
        draft.sourceURL = url.absoluteString
        draft.method = "social"
        return draft
    }

    /// Pulls the description / caption out of the page's meta tags or VideoObject JSON-LD.
    static func caption(fromHTML html: String) -> String {
        guard !html.isEmpty else { return "" }
        for json in RecipeSchemaParser.jsonLDBlocks(in: html) {
            if let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)), let dictionary = findVideo(in: object),
               let description = RecipeSchemaParser.text(dictionary["description"]), description.count > 30 {
                return description
            }
        }
        for property in ["og:description", "twitter:description", "description"] {
            let pattern = #"<meta[^>]+(?:property|name)\s*=\s*["']\#(property)["'][^>]+content\s*=\s*["']([^"']*)["']"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let content = HTMLText.decode(String(html[range]))
                if content.count > 30 { return content }
            }
        }
        return ""
    }

    private static func findVideo(in object: Any) -> [String: Any]? {
        if let dictionary = object as? [String: Any] {
            if let type = dictionary["@type"] as? String, ["VideoObject", "SocialMediaPosting", "Article"].contains(type) { return dictionary }
            for key in ["@graph", "mainEntity"] { if let nested = dictionary[key], let found = findVideo(in: nested) { return found } }
            return nil
        }
        if let array = object as? [Any] { for element in array { if let found = findVideo(in: element) { return found } } }
        return nil
    }
}
