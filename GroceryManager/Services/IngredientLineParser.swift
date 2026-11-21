import Foundation

struct ParsedIngredientLine: Equatable {
    var quantity: Double
    var unit: String
    var name: String
    var note: String
}

/// Turns free-text ingredient lines ("2 ½ cups all-purpose flour, sifted") into structured
/// quantities, so imported recipes merge and convert like hand-entered ones.
enum IngredientLineParser {
    static func parse(_ rawLine: String) -> ParsedIngredientLine {
        var line = HTMLText.decode(rawLine)
            .replacingOccurrences(of: #"^[\s\-\*•·▢◻☐]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        line = normalizeFractions(line)

        var quantity: Double?
        var unit = QuantityUnit.item.rawValue
        var note: [String] = []

        // Leading amount, possibly a range: "2", "1/2", "1 1/2", "2-3", "2 to 3", ".5"
        let amountPattern = #"^((?:\d+\s+\d+/\d+)|(?:\d+/\d+)|(?:\d*\.\d+)|(?:\d+))(?:\s*(?:-|–|—|to)\s*((?:\d+\s+\d+/\d+)|(?:\d+/\d+)|(?:\d*\.\d+)|(?:\d+)))?\s*"#
        if let match = line.range(of: amountPattern, options: .regularExpression) {
            let matched = String(line[match])
            let parts = matched.components(separatedBy: CharacterSet(charactersIn: "-–—")).map { $0.replacingOccurrences(of: "to", with: "").trimmingCharacters(in: .whitespaces) }
            quantity = number(from: parts[0])
            if parts.count > 1, let upper = number(from: parts[1]), let lower = quantity {
                note.append("\(lower.quantityText)–\(upper.quantityText)")
            }
            line.removeSubrange(match)
        }

        // Package size right after the amount: "1 (14 oz) can", "2 (14.5-ounce) tins". A
        // parenthetical that isn't a weight or volume ("6 (12 inch) tortillas") is just a note.
        if let regex = try? NSRegularExpression(pattern: #"^\(\s*(\d+(?:\.\d+)?|\d+/\d+)\s*-?\s*([a-zA-Z .]+?)\s*\)\s*"#),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let whole = Range(match.range, in: line),
           let sizeRange = Range(match.range(at: 1), in: line),
           let unitRange = Range(match.range(at: 2), in: line) {
            let inner = String(line[whole]).trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            if let size = number(from: String(line[sizeRange])), let sizeUnit = unitAlias(String(line[unitRange])) {
                quantity = (quantity ?? 1) * size
                unit = sizeUnit
            }
            note.append(inner)
            line.removeSubrange(whole)
        }

        // Unit word(s) after the amount.
        var words = line.split(separator: " ").map(String.init)
        if !words.isEmpty {
            let unitIsOpen = unit == QuantityUnit.item.rawValue
            if unitIsOpen, words.count >= 2, let two = unitAlias("\(words[0]) \(words[1])") {
                unit = two
                words.removeFirst(2)
            } else if unitIsOpen, let one = unitAlias(words[0]) {
                unit = one
                words.removeFirst()
            } else if let container = containerWord(words[0]) {
                note.append(container)
                words.removeFirst()
            }
        }
        if words.first?.lowercased() == "of" { words.removeFirst() }

        // Parentheticals anywhere → note
        let cleaned = stripParentheticals(words.joined(separator: " "))
        var rest = cleaned.text
        note += cleaned.notes
        // "name, note"
        var name = rest
        if let comma = rest.firstIndex(of: ",") {
            name = String(rest[..<comma])
            let tail = rest[rest.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { note.append(tail) }
        }
        // "salt to taste", "flour for dusting"
        for phrase in ["to taste", "for serving", "for garnish", "for dusting", "for greasing", "as needed", "or to taste"] {
            if let range = name.range(of: phrase, options: .caseInsensitive) {
                note.append(phrase)
                name.removeSubrange(range)
            }
        }
        name = name.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))

        // Size words belong in the note so "large eggs" matches "eggs".
        let sizeWords = ["large", "medium", "small", "extra-large", "jumbo"]
        var nameWords = name.split(separator: " ").map(String.init)
        if let first = nameWords.first?.lowercased(), sizeWords.contains(first) {
            note.append(nameWords.removeFirst())
            name = nameWords.joined(separator: " ")
        }

        return ParsedIngredientLine(
            quantity: quantity ?? 1,
            unit: unit,
            name: name.isEmpty ? rawLine.trimmingCharacters(in: .whitespaces) : name,
            note: note.joined(separator: ", ")
        )
    }

    /// Moves every "(…)" into notes and drops unmatched brackets, so names like
    /// "flour tortillas (12 inches" or "16 ounces) refried beans" come out clean.
    static func stripParentheticals(_ text: String) -> (text: String, notes: [String]) {
        var output = ""
        var notes: [String] = []
        var depth = 0
        var current = ""
        for character in text {
            switch character {
            case "(", "[":
                if depth == 0 { current = "" } else { current.append(character) }
                depth += 1
            case ")", "]":
                if depth == 0 {
                    // Unmatched close: everything before it was a parenthetical that lost its "(".
                    let orphan = output.trimmingCharacters(in: .whitespaces)
                    if !orphan.isEmpty, orphan.first?.isNumber == true {
                        notes.append(orphan)
                        output = ""
                    }
                    continue
                }
                depth -= 1
                if depth == 0 {
                    let inner = current.trimmingCharacters(in: .whitespaces)
                    if !inner.isEmpty { notes.append(inner) }
                    output.append(" ")
                } else {
                    current.append(character)
                }
            default:
                if depth == 0 { output.append(character) } else { current.append(character) }
            }
        }
        // Unclosed "(": what follows it is the note.
        let tail = current.trimmingCharacters(in: .whitespaces)
        if depth > 0, !tail.isEmpty { notes.append(tail) }
        let text = output
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;-")))
        return (text, notes)
    }

    /// Cleans an ingredient name that came from somewhere other than `parse`, such as the
    /// on-device model: drops parentheticals and leading container words into the note.
    static func cleanName(_ rawName: String) -> (name: String, note: String) {
        var (text, notes) = stripParentheticals(HTMLText.decode(rawName))
        var words = text.split(separator: " ").map(String.init)
        if words.count > 1, let container = containerWord(words[0]) {
            notes.append(container)
            words.removeFirst()
            if words.first?.lowercased() == "of" { words.removeFirst() }
        }
        text = words.joined(separator: " ")
        return (text.isEmpty ? rawName.trimmingCharacters(in: .whitespaces) : text, notes.joined(separator: ", "))
    }

    // MARK: Helpers

    private static func number(from text: String) -> Double? {
        let pieces = text.split(separator: " ")
        var total = 0.0
        for piece in pieces {
            if piece.contains("/") {
                let frac = piece.split(separator: "/")
                guard frac.count == 2, let n = Double(frac[0]), let d = Double(frac[1]), d != 0 else { return nil }
                total += n / d
            } else if let value = Double(piece) {
                total += value
            } else {
                return nil
            }
        }
        return pieces.isEmpty ? nil : total
    }

    private static let unicodeFractions: [Character: String] = [
        "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4",
        "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5", "⅙": "1/6", "⅚": "5/6",
        "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8"
    ]

    static func normalizeFractions(_ text: String) -> String {
        var output = ""
        for character in text {
            if let fraction = unicodeFractions[character] {
                if let last = output.last, last.isNumber { output.append(" ") }
                output.append(fraction)
            } else {
                output.append(character)
            }
        }
        return output
    }

    static func unitAlias(_ word: String) -> String? {
        let cleaned = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        return aliases[cleaned]
    }

    private static let aliases: [String: String] = {
        var map: [String: String] = [:]
        func add(_ unit: QuantityUnit, _ words: [String]) { for word in words { map[word] = unit.rawValue } }
        add(.teaspoons, ["tsp", "tsps", "teaspoon", "teaspoons", "t"])
        add(.tablespoons, ["tbsp", "tbsps", "tbs", "tablespoon", "tablespoons", "tbl"])
        add(.cups, ["cup", "cups", "c"])
        add(.pints, ["pint", "pints", "pt", "pts"])
        add(.quarts, ["quart", "quarts", "qt", "qts"])
        add(.gallons, ["gallon", "gallons", "gal"])
        add(.fluidOunces, ["fl oz", "fl. oz", "fl.oz", "fluid ounce", "fluid ounces", "floz"])
        add(.ounces, ["oz", "ozs", "ounce", "ounces"])
        add(.pounds, ["lb", "lbs", "pound", "pounds"])
        add(.grams, ["g", "gr", "gram", "grams", "gm"])
        add(.kilograms, ["kg", "kgs", "kilogram", "kilograms", "kilo", "kilos"])
        add(.milliliters, ["ml", "mls", "milliliter", "milliliters", "millilitre", "millilitres"])
        add(.liters, ["l", "liter", "liters", "litre", "litres"])
        add(.pinches, ["pinch", "pinches"])
        add(.dashes, ["dash", "dashes"])
        add(.dozen, ["dozen", "doz"])
        add(.serving, ["serving", "servings", "portion", "portions"])
        map.removeValue(forKey: "t") // too ambiguous between tsp and tbsp
        return map
    }()

    private static let containers = ["can", "cans", "tin", "tins", "jar", "jars", "package", "packages", "pkg", "packet", "packets", "bottle", "bottles", "bunch", "bunches", "clove", "cloves", "slice", "slices", "stalk", "stalks", "sprig", "sprigs", "head", "heads", "piece", "pieces", "ear", "ears", "fillet", "fillets", "stick", "sticks", "sheet", "sheets", "whole", "box", "boxes", "bag", "bags", "handful", "scoop", "scoops", "knob", "block", "cube", "cubes", "leaf", "leaves", "strip", "strips", "rack", "loaf", "container", "envelope", "envelopes", "pouch", "pouches", "carton", "cartons", "tube", "tubes", "sachet", "sachets", "tub", "tubs"]

    static func containerWord(_ word: String) -> String? {
        let cleaned = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        return containers.contains(cleaned) ? cleaned : nil
    }
}

/// Minimal HTML text helpers used by the importers.
enum HTMLText {
    private static let entities: [String: String] = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
        "&frac12;": "½", "&frac14;": "¼", "&frac34;": "¾", "&deg;": "°", "&ndash;": "–", "&mdash;": "—",
        "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“", "&hellip;": "…", "&eacute;": "é"
    ]

    static func decode(_ text: String) -> String {
        var output = text
        for (entity, value) in entities { output = output.replacingOccurrences(of: entity, with: value) }
        // Numeric entities: &#8217; and &#x2019;
        let pattern = #"&#(x?)([0-9a-fA-F]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return output }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output)).reversed()
        for match in matches {
            guard let isHexRange = Range(match.range(at: 1), in: output),
                  let valueRange = Range(match.range(at: 2), in: output),
                  let whole = Range(match.range, in: output) else { continue }
            let isHex = !output[isHexRange].isEmpty
            guard let code = UInt32(output[valueRange], radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) else { continue }
            output.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return output
    }

    static func stripTags(_ html: String) -> String {
        decode(html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func plainText(fromDocument html: String) -> String {
        stripTags(html
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: " ", options: .regularExpression))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
