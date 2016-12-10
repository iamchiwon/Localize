#!/usr/bin/env xcrun --sdk macosx swift

import Foundation


// WHAT
// 1. Find Missing keys in other Localisation files
// 2. Find potentially untranslated keys
// 3. Find Duplicate keys
// 4. Find Unused keys and generate script to delete them all at once

/*
 Put your path here, example ->  Resources/Localizations/Languages
 */
let relativeLocalizableFolders = "/Resources/Languages"

/*
 This is the path of your source folder which will be used in searching
 for the localization keys you actually use in your project
 */
let relativeSourceFolder = ""

/*
 Those are the regex patterns to recognize localizations.
 */
let patterns = [
    "NSLocalizedString\\(@?\"(\\w+)\"", // Swift and Objc Native
    "Localizations\\.((?:[A-Z]{1}[a-z]*[A-z]*)*(?:\\.[A-Z]{1}[a-z]*[A-z]*)*)" // Laurine Calls
]

/*
 Those are the keys you don't want to be recognized as "unused"
 For instance, Keys that you concatenate will not be detected by the parsing
 so you want to add them here in order not to create false positives :)
 */
let ignoredFromUnusedKeys = []
/* example
let ignoredFromUnusedKeys = [
    "NotificationNoOne",
    "NotificationCommentPhoto",
    "NotificationCommentHisPhoto",
    "NotificationCommentHerPhoto"
]
*/

var ignoredFromSameTranslation = [String:[String]]()


let path = FileManager.default.currentDirectoryPath + relativeLocalizableFolders
var numberOfWarnings = 0

struct LocalizationFiles {
    var name = ""
    var keyValue = [String:String]()
    var linesNumbers = [String:Int]()

    init(name: String) {
        self.name = name
        process()
    }

    mutating func process() {
        let location = "\(path)/\(name).lproj/Localizable.strings"
        if let string = try? String(contentsOfFile: location, encoding: .utf8) {
            let lines =  string.components(separatedBy: CharacterSet.newlines)
            keyValue = [String:String]()
            let pattern = "\"(.*)\" = \"(.+)\";"
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            var ignoredTranslation = [String]()

            for (lineNumber, line) in lines.enumerated() {
                let range = NSRange(location:0, length:(line as NSString).length)


                // Ignored pattern
                let ignoredPattern = "\"(.*)\" = \"(.+)\"; *\\/\\/ *ignore-same-translation-warning"
                let ignoredRegex = try? NSRegularExpression(pattern: ignoredPattern, options: [])
                if let ignoredMatch = ignoredRegex?.firstMatch(in:line,
                                                                       options: [],
                                                                       range: range) {
                    let key = (line as NSString).substring(with: ignoredMatch.rangeAt(1))
                    ignoredTranslation.append(key)
                }
                if let firstMatch = regex?.firstMatch(in: line, options: [], range: range) {
                    let key = (line as NSString).substring(with: firstMatch.rangeAt(1))
                    let value = (line as NSString).substring(with: firstMatch.rangeAt(2))
                    if let _ =  keyValue[key] {
                        let str = "\(path)/\(name).lproj"
                        + "/Localizable.strings:\(linesNumbers[key]!): "
                        + "error : [Redundance] \"\(key)\" "
                        + "is redundant in \(name.uppercased()) file"
                        print(str)
                        numberOfWarnings += 1
                    } else {
                        keyValue[key] = value
                        linesNumbers[key] = lineNumber+1
                    }
                }
            }
            print(ignoredFromSameTranslation)
            ignoredFromSameTranslation[name] = ignoredTranslation
        }
    }
}

// MARK: - Load Localisation Files in memory

let en = LocalizationFiles(name: "en")
let es = LocalizationFiles(name: "es")
let fr = LocalizationFiles(name: "fr")
let localizationFiles = [fr, es]



// MARK: - Detect Unused Keys

let sourcesPath = FileManager.default.currentDirectoryPath + relativeSourceFolder
let fileManager = FileManager.default
let enumerator = fileManager.enumerator(atPath:sourcesPath)
var localizedStrings = [String]()
while let swiftFileLocation = enumerator?.nextObject() as? String {
    // checks the extension // TODO OBJC?
    if swiftFileLocation.hasSuffix(".swift") ||  swiftFileLocation.hasSuffix(".m") {
        let location = "\(sourcesPath)/\(swiftFileLocation)"
        if let string = try? String(contentsOfFile: location, encoding: .utf8) {
            for p in patterns {
                let regex = try? NSRegularExpression(pattern: p, options: [])
                let range = NSRange(location:0, length:(string as NSString).length) //Obj c wa
                regex?.enumerateMatches(in: string,
                                                options: [],
                                                range: range,
                                                using: { (result, _, _) in
                    if let r = result {
                        let value = (string as NSString).substring(with:r.rangeAt(1))
                        localizedStrings.append(value)
                    }
                })
            }
        }
    }
}

var masterKeys = Set(en.keyValue.keys)
let usedKeys = Set(localizedStrings)
let ignored = Set(ignoredFromUnusedKeys)
let unused = masterKeys.subtracting(usedKeys).subtracting(ignored)

// Here generate Xcode regex Find and replace script to remove dead keys all at once!
var replaceCommand = "\"("
var counter = 0
for v in unused {
    var str = "\(path)/\(en.name).lproj/Localizable.strings:\(en.linesNumbers[v]!): "
    str += "error : [Unused Key] \"\(v)\" is never used"
    print(str)
    if counter != 0 {
        replaceCommand += "|"
    }
    replaceCommand += v
    if counter == unused.count-1 {
        replaceCommand += ")\" = \".*\";"
    }
    counter += 1
}

print(replaceCommand)


// MARK: - Compare each translation file against master (en)

for file in localizationFiles {
    for k in en.keyValue.keys {
        if let v = file.keyValue[k] {
            if v == en.keyValue[k] {
                if !ignoredFromSameTranslation[file.name]!.contains(k) {
                    var str = "\(path)/\(file.name).lproj/Localizable.strings"
                    + ":\(file.linesNumbers[k]!): "
                    + "warning: [Potentialy Untranslated] \"\(k)\""
                    + "in \(file.name.uppercased()) file doesn't seem to be localized"
                    print(str)
                    numberOfWarnings += 1
                }
            }
        } else {
            var str = "\(path)/\(file.name).lproj/Localizable.strings:\(en.linesNumbers[k]!): "
            str += "error: [Missing] \"\(k)\" missing form \(file.name.uppercased()) file"
            print(str)
        }
    }
}

print("Number of warnings : \(numberOfWarnings)")