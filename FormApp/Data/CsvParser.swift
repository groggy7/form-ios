import Foundation

public enum CsvParser {

    public static func detectDelimiter(_ headerLine: String) -> Character {
        let semicolons = headerLine.filter { $0 == ";" }.count
        let commas = headerLine.filter { $0 == "," }.count
        let tabs = headerLine.filter { $0 == "\t" }.count
        if semicolons > commas && semicolons > tabs {
            return ";"
        } else if tabs > commas && tabs > semicolons {
            return "\t"
        } else {
            return ","
        }
    }

    public static func parse(_ csvText: String, delimiter: Character? = nil) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        let characters = Array(csvText)
        var i = 0
        let count = characters.count

        // Detect delimiter from first line if not provided
        var actualDelimiter: Character = delimiter ?? ","
        if delimiter == nil {
            var firstLineChars: [Character] = []
            var j = 0
            while j < count && characters[j] != "\n" && characters[j] != "\r" {
                firstLineChars.append(characters[j])
                j += 1
            }
            actualDelimiter = detectDelimiter(String(firstLineChars))
        }

        while i < count {
            let c = characters[i]
            if c == "\"" {
                if inQuotes {
                    if i + 1 < count && characters[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if c == actualDelimiter && !inQuotes {
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else if (c == "\n" || c == "\r") && !inQuotes {
                if c == "\r" && i + 1 < count && characters[i + 1] == "\n" {
                    i += 1
                }
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
                if currentRow.contains(where: { !$0.isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
            } else {
                currentField.append(c)
            }
            i += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if currentRow.contains(where: { !$0.isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }
}
