//
//  ProgramImportParser.swift
//  SpottersaurusKit
//
//  Pure `String -> ProgramImportResult` parser for pasted coach-shorthand
//  program text (see docs/specs/2026-08-05-custom-program-import.md). Turns a
//  freeform Portuguese-language weekly block — numbered days, ramp/pyramid
//  set schemes, RPE accessory shorthand, `Intervalo:` rest notes, `(Filmar)`
//  film reminders, `OFF/DESCANSO` rest days — into a `ProgramDraft` that
//  opens in the existing Program Builder for review. Best-effort: never
//  throws, never drops information it can't classify — unrecognized text is
//  preserved as a `ProgramImportNote` instead.
//

import Foundation

/// The result of parsing a pasted program block: the structured draft, plus
/// any lines/tokens the parser couldn't confidently classify, surfaced for
/// user review rather than silently dropped.
public struct ProgramImportResult {
    public var draft: ProgramDraft
    public var notes: [ProgramImportNote]

    public init(draft: ProgramDraft, notes: [ProgramImportNote] = []) {
        self.draft = draft
        self.notes = notes
    }
}

/// A single piece of source text the parser preserved rather than dropped.
public struct ProgramImportNote: Equatable {
    /// Index into `ProgramImportResult.draft.days`, or `nil` for a
    /// program-level note (e.g. free text above the first `Dia` block).
    public var dayIndex: Int?
    /// The exercise this note concerns, or `nil` for a day-level note.
    public var exerciseName: String?
    /// The preserved text.
    public var text: String

    public init(dayIndex: Int? = nil, exerciseName: String? = nil, text: String) {
        self.dayIndex = dayIndex
        self.exerciseName = exerciseName
        self.text = text
    }
}

/// Pure parser: pasted coach-shorthand text -> `ProgramImportResult`.
public enum ProgramImportParser {

    /// Parses a full pasted program block into a draft + review notes. Never
    /// throws; text it can't confidently classify is preserved as a note.
    public static func parse(_ text: String) -> ProgramImportResult {
        let dayMatches = matches(of: dayHeaderPattern, in: text)

        var notes: [ProgramImportNote] = []

        // Text before the first "Dia N)" header: scan for "Mesociclo X/Semana Y"
        // and preserve any other non-blank lines as program-level notes.
        let firstDayStart = dayMatches.first.flatMap { Range($0.range, in: text) }?.lowerBound ?? text.endIndex
        let headerText = String(text[text.startIndex..<firstDayStart])
        let (mesocycleNumber, weekNumber) = extractMesocycleWeek(from: headerText)
        for line in lines(of: headerText) where mesocycleWeekPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil {
            notes.append(ProgramImportNote(dayIndex: nil, exerciseName: nil, text: line))
        }

        var days: [ProgramDayDraft] = []

        for (index, match) in dayMatches.enumerated() {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let dayNumber = (Range(match.range(at: 1), in: text)).flatMap { Int(text[$0]) } ?? (index + 1)
            let blockStart = matchRange.upperBound
            let blockEnd = index + 1 < dayMatches.count
                ? Range(dayMatches[index + 1].range, in: text)?.lowerBound ?? text.endIndex
                : text.endIndex
            let blockText = String(text[blockStart..<blockEnd])
            let dayLines = lines(of: blockText)

            let dayName = "Day \(dayNumber)"
            if isOffDay(dayLines) {
                days.append(ProgramDayDraft(name: dayName, sets: []))
                continue
            }

            let (exercises, dayLevelNotes) = parseDayBody(dayLines)
            let dayIndex = days.count
            var sets: [PlannedSetDraft] = []
            for exercise in exercises {
                sets.append(contentsOf: exercise.makeSets())
                for noteText in exercise.reviewNotes() {
                    notes.append(ProgramImportNote(dayIndex: dayIndex, exerciseName: exercise.name, text: noteText))
                }
            }
            for noteText in dayLevelNotes {
                notes.append(ProgramImportNote(dayIndex: dayIndex, exerciseName: nil, text: noteText))
            }
            days.append(ProgramDayDraft(name: dayName, sets: sets))
        }

        let draft = ProgramDraft(days: days, mesocycleNumber: mesocycleNumber, weekNumber: weekNumber)
        return ProgramImportResult(draft: draft, notes: notes)
    }

    // MARK: - Day header / mesocycle

    private static let dayHeaderPattern = try! NSRegularExpression(pattern: #"Dia\s*(\d+)\s*\)"#, options: [.caseInsensitive])
    private static let mesocycleWeekPattern = try! NSRegularExpression(pattern: #"Mesociclo\s*(\d+)\s*/\s*Semana\s*(\d+)"#, options: [.caseInsensitive])

    private static func extractMesocycleWeek(from headerText: String) -> (Int?, Int?) {
        guard let match = mesocycleWeekPattern.firstMatch(in: headerText, range: NSRange(headerText.startIndex..., in: headerText)) else {
            return (nil, nil)
        }
        let meso = Range(match.range(at: 1), in: headerText).flatMap { Int(headerText[$0]) }
        let week = Range(match.range(at: 2), in: headerText).flatMap { Int(headerText[$0]) }
        return (meso, week)
    }

    /// Whether a day's body is nothing but `OFF`/`DESCANSO` tokens (case- and
    /// accent-insensitive, PT or EN) — an explicit rest day, not a gap.
    private static func isOffDay(_ dayLines: [String]) -> Bool {
        guard !dayLines.isEmpty else { return false }
        let joined = dayLines.joined(separator: " ")
        let normalized = joined.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).uppercased()
        let tokens = normalized.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return false }
        return tokens.allSatisfy { $0 == "OFF" || $0 == "DESCANSO" }
    }

    // MARK: - Day body

    /// One exercise's worth of parsed coach shorthand: its name, flags, free
    /// text notes, and the raw (still-unsplit) set-list text collected from
    /// one or more source lines.
    private struct ExerciseBlock {
        var name: String
        var filmReminder = false
        var parenNotes: [String] = []
        var setsBlobParts: [String] = []
        var hasSeenSetsLine = false
        var restSeconds: Int?
        var malformedIntervalCount = 0

        /// Expands this block's raw set-list text into concrete
        /// `PlannedSetDraft`s, applying the block's lift/flags/rest to each.
        func makeSets() -> [PlannedSetDraft] {
            let lift = ProgramImportParser.liftKind(for: name)
            let blob = setsBlobParts.joined(separator: ", ")
            let (tokens, _) = ProgramImportParser.parseSetTokens(blob)
            return tokens.map { token in
                PlannedSetDraft(
                    lift: lift,
                    customExerciseName: lift == .accessory ? name : "",
                    targetReps: token.reps,
                    load: token.load,
                    isAMRAP: false,
                    restSeconds: restSeconds ?? 180,
                    filmReminder: filmReminder
                )
            }
        }

        /// Free text worth surfacing to the user: parenthetical notes,
        /// unrecognized set tokens, and malformed `Intervalo` durations.
        func reviewNotes() -> [String] {
            var out = parenNotes
            let blob = setsBlobParts.joined(separator: ", ")
            let (_, unrecognized) = ProgramImportParser.parseSetTokens(blob)
            out.append(contentsOf: unrecognized.map { "Unrecognized set token: \"\($0)\"" })
            if malformedIntervalCount > 0 {
                out.append("Unparsed rest duration (\(malformedIntervalCount) Intervalo line(s))")
            }
            return out
        }
    }

    /// Walks a day's (already Intervalo-stripped-per-line) content, grouping
    /// lines into exercise blocks per the coach-shorthand rules described in
    /// the spec's "New ProgramImportParser" section.
    private static func parseDayBody(_ dayLines: [String]) -> (exercises: [ExerciseBlock], dayNotes: [String]) {
        var exercises: [ExerciseBlock] = []
        var current: ExerciseBlock?
        var dayNotes: [String] = []

        func finalizeCurrent() {
            if let block = current { exercises.append(block) }
            current = nil
        }

        for rawLine in dayLines {
            let (content, intervalDurations) = extractIntervalMentions(from: rawLine)
            let trimmedContent = content.trimmingCharacters(in: .whitespaces)

            if !trimmedContent.isEmpty {
                if let setsRange = firstSetsTokenRange(in: trimmedContent) {
                    if setsRange.lowerBound == trimmedContent.startIndex {
                        // Case A: a pure set-list continuation line.
                        if current == nil {
                            current = ExerciseBlock(name: "")
                            dayNotes.append("Sets with no preceding exercise name: \"\(trimmedContent)\"")
                        }
                        current?.setsBlobParts.append(trimmedContent)
                        current?.hasSeenSetsLine = true
                    } else {
                        // Case B: "<name> <sets>" on one line — start a new exercise.
                        finalizeCurrent()
                        let namePart = String(trimmedContent[trimmedContent.startIndex..<setsRange.lowerBound])
                        let setsPart = String(trimmedContent[setsRange.lowerBound...])
                        let (name, filmReminder, parenNotes) = extractNameAndFlags(namePart)
                        var block = ExerciseBlock(name: name, filmReminder: filmReminder, parenNotes: parenNotes)
                        block.setsBlobParts.append(setsPart)
                        block.hasSeenSetsLine = true
                        current = block
                    }
                } else {
                    // Case C: a name-only (or note-only) line.
                    if current != nil && current!.hasSeenSetsLine == false {
                        // Continues the still-being-named current exercise.
                        let (leftoverName, filmReminder, parenNotes) = extractNameAndFlags(trimmedContent)
                        if filmReminder { current?.filmReminder = true }
                        current?.parenNotes.append(contentsOf: parenNotes)
                        if !leftoverName.isEmpty {
                            let existingName = current?.name ?? ""
                            current?.name = existingName.isEmpty ? leftoverName : "\(existingName) \(leftoverName)"
                        }
                    } else {
                        finalizeCurrent()
                        let (name, filmReminder, parenNotes) = extractNameAndFlags(trimmedContent)
                        current = ExerciseBlock(name: name, filmReminder: filmReminder, parenNotes: parenNotes)
                    }
                }
            }

            for durationText in intervalDurations {
                if current == nil {
                    current = ExerciseBlock(name: "")
                }
                if let seconds = parseDuration(durationText) {
                    current?.restSeconds = seconds
                } else {
                    current?.malformedIntervalCount += 1
                }
            }
        }

        finalizeCurrent()
        return (exercises, dayNotes)
    }

    /// Extracts every `Intervalo: <duration>` mention from a line, returning
    /// the line with those spans removed (and dangling separators trimmed)
    /// alongside the raw duration text for each mention (empty string if the
    /// duration was missing/malformed).
    private static func extractIntervalMentions(from line: String) -> (content: String, durations: [String]) {
        var remaining = line
        var durations: [String] = []
        while let match = intervalPattern.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
              let matchRange = Range(match.range, in: remaining) {
            let durationRange = Range(match.range(at: 1), in: remaining)
            let duration = durationRange.map { remaining[$0].trimmingCharacters(in: .whitespaces) } ?? ""
            durations.append(duration)
            remaining.removeSubrange(matchRange)
        }
        var content = remaining.trimmingCharacters(in: .whitespaces)
        while let last = content.last, last == "/" || last == "," {
            content.removeLast()
            content = content.trimmingCharacters(in: .whitespaces)
        }
        return (content, durations)
    }

    private static let intervalPattern = try! NSRegularExpression(pattern: #"Intervalo\s*:\s*([^,]*)$"#, options: [.caseInsensitive])

    /// Parses a free-text rest duration: plain seconds (`90s`), minutes
    /// (`2mins`), or a minute range (`4-5mins`, upper bound used). `nil` for
    /// missing/malformed text.
    private static func parseDuration(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let match = firstMatch(of: minuteRangePattern, in: trimmed),
           let upperRange = Range(match.range(at: 2), in: trimmed),
           let upper = Int(trimmed[upperRange]) {
            return upper * 60
        }
        if let match = firstMatch(of: minutesPattern, in: trimmed),
           let valueRange = Range(match.range(at: 1), in: trimmed),
           let value = Int(trimmed[valueRange]) {
            return value * 60
        }
        if let match = firstMatch(of: secondsPattern, in: trimmed),
           let valueRange = Range(match.range(at: 1), in: trimmed),
           let value = Int(trimmed[valueRange]) {
            return value
        }
        return nil
    }

    private static let minuteRangePattern = try! NSRegularExpression(pattern: #"^(\d+)\s*-\s*(\d+)\s*min(?:s|utos?|utes?)?$"#, options: [.caseInsensitive])
    private static let minutesPattern = try! NSRegularExpression(pattern: #"^(\d+)\s*min(?:s|utos?|utes?)?$"#, options: [.caseInsensitive])
    private static let secondsPattern = try! NSRegularExpression(pattern: #"^(\d+)\s*s(?:ecs?|econds?|egs?|egundos?)?$"#, options: [.caseInsensitive])

    // MARK: - Exercise name / flags

    /// Splits a name-portion string into the leftover display name plus any
    /// parenthetical groups it contained — `(Filmar)` sets the film-reminder
    /// flag, everything else is kept as a free-text note.
    private static func extractNameAndFlags(_ text: String) -> (name: String, filmReminder: Bool, notes: [String]) {
        var remainder = text
        var notes: [String] = []
        var filmReminder = false
        while let match = firstMatch(of: parenGroupPattern, in: remainder),
              let matchRange = Range(match.range, in: remainder) {
            let innerRange = Range(match.range(at: 1), in: remainder)
            let inner = innerRange.map { remainder[$0].trimmingCharacters(in: .whitespaces) } ?? ""
            let normalized = inner.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if normalized == "filmar" {
                filmReminder = true
            } else if !inner.isEmpty {
                notes.append(inner)
            }
            remainder.removeSubrange(matchRange)
        }
        let name = remainder.trimmingCharacters(in: .whitespaces)
        return (name, filmReminder, notes)
    }

    private static let parenGroupPattern = try! NSRegularExpression(pattern: #"\(([^)]*)\)"#)

    /// Location of the first ramp-step (`60/7`) or RPE-shorthand (`4x12@9`)
    /// token start in `text`, used to split an inline "name + sets" line.
    private static func firstSetsTokenRange(in text: String) -> Range<String.Index>? {
        let rpeMatch = firstMatch(of: rpeStartPattern, in: text).flatMap { Range($0.range, in: text) }
        let rampMatch = firstMatch(of: rampStartPattern, in: text).flatMap { Range($0.range, in: text) }
        switch (rpeMatch, rampMatch) {
        case (nil, nil): return nil
        case (let r?, nil): return r
        case (nil, let r?): return r
        case (let r1?, let r2?): return r1.lowerBound <= r2.lowerBound ? r1 : r2
        }
    }

    private static let rpeStartPattern = try! NSRegularExpression(pattern: #"\d+\s*[xX]\s*\d+\s*@\s*\d+(?:[.,]\d+)?"#)
    private static let rampStartPattern = try! NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?\s*(?:kg)?\s*/\s*\d+"#)

    // MARK: - Set-list tokens

    /// Parses a comma-separated set-list blob into concrete
    /// `(reps, load)` pairs (expanding `xN sets`/`NxR@RPE` shorthand into N
    /// repeated entries) plus any tokens that couldn't be classified.
    private static func parseSetTokens(_ blob: String) -> (sets: [(reps: Int, load: PlannedSetLoadDraft)], unrecognized: [String]) {
        var sets: [(reps: Int, load: PlannedSetLoadDraft)] = []
        var unrecognized: [String] = []

        for rawToken in splitSetTokens(blob) {
            let token = rawToken.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }

            if let match = firstMatch(of: rpeTokenPattern, in: token) {
                let n = intGroup(match, 1, in: token) ?? 1
                let reps = intGroup(match, 2, in: token) ?? 0
                let rpe = doubleGroup(match, 3, in: token) ?? 0
                for _ in 0..<max(1, n) {
                    sets.append((reps: reps, load: PlannedSetLoadDraft(kind: .rpe, value: rpe)))
                }
                continue
            }

            if let match = firstMatch(of: rampTokenPattern, in: token) {
                let weight = doubleGroup(match, 1, in: token) ?? 0
                let reps = intGroup(match, 2, in: token) ?? 0
                let n = intGroup(match, 3, in: token) ?? 1
                for _ in 0..<max(1, n) {
                    sets.append((reps: reps, load: PlannedSetLoadDraft(kind: .absolute, value: weight)))
                }
                continue
            }

            unrecognized.append(token)
        }

        return (sets, unrecognized)
    }

    /// `NxR@RPE`, tolerant of a missing/mismatched `(RPE)` suffix — e.g.
    /// `4x12@9(RPE)`, `4x12@9RPE)`, or bare `3x12@9`.
    private static let rpeTokenPattern = try! NSRegularExpression(
        pattern: #"^(\d+)\s*[xX]\s*(\d+)\s*@\s*(\d+(?:[.,]\d+)?)\s*\(?\s*(?:RPE)?\s*\)?$"#,
        options: [.caseInsensitive]
    )

    /// `weight[kg]/reps[reps][xNsets]` — a ramp step, optionally expanded by
    /// a trailing `xN sets` (or the coach's typo'd `xN reps`).
    private static let rampTokenPattern = try! NSRegularExpression(
        pattern: #"^(\d+(?:[.,]\d+)?)\s*(?:kg)?\s*/\s*(\d+)\s*(?:reps?)?\s*(?:[xX]\s*(\d+)\s*(?:sets?|reps?))?$"#,
        options: [.caseInsensitive]
    )

    /// Splits a set-list blob on comma **list separators**, while treating a
    /// comma inside a decimal weight (e.g. `87,5`) as part of the number
    /// rather than a split point — a comma followed by exactly one digit
    /// (then a non-digit or end of string) is a decimal separator; any other
    /// comma after a digit is a list separator.
    private static func splitSetTokens(_ blob: String) -> [String] {
        let placeholder = "\u{0}"
        let range = NSRange(blob.startIndex..., in: blob)
        let protectedBlob = decimalCommaPattern.stringByReplacingMatches(in: blob, range: range, withTemplate: placeholder)
        return protectedBlob.components(separatedBy: ",").map { $0.replacingOccurrences(of: placeholder, with: ",") }
    }

    private static let decimalCommaPattern = try! NSRegularExpression(pattern: #"(?<=\d),(?=\d(?:\D|$))"#)

    // MARK: - PT lift-name mapping

    /// "Agachamento" (+ variants) -> squat, "Supino" (+ variants) -> bench,
    /// "Levantamento Terra" -> deadlift; anything else -> accessory, keeping
    /// the parsed name verbatim.
    private static func liftKind(for name: String) -> LiftKind {
        let normalized = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if normalized.contains("levantamento terra") { return .deadlift }
        if normalized.contains("agachamento") { return .squat }
        if normalized.contains("supino") { return .bench }
        return .accessory
    }

    // MARK: - Regex / substring helpers

    private static func matches(of pattern: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func firstMatch(of pattern: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func intGroup(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> Int? {
        guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }

    private static func doubleGroup(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> Double? {
        guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    /// Splits text into trimmed, non-blank lines.
    private static func lines(of text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
