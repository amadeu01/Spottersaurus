//
//  ProgramImportParserTests.swift
//  SpottersaurusKitTests
//
//  Coverage for `ProgramImportParser`, the pure coach-shorthand text ->
//  `ProgramImportResult` parser (docs/specs/2026-08-05-custom-program-import.md).
//  Exercises each shorthand rule in isolation, then locks the exact real-world
//  fixture from the spec's sourcing conversation as a golden regression test.
//

import XCTest
@testable import SpottersaurusKit

final class ProgramImportParserTests: XCTestCase {

    // MARK: Ramp-step expansion

    func testRampStepsEachBecomeOneSet() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        20/15, 60/7, 100/4
        """)

        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets.map(\.load), [
            PlannedSetLoadDraft(kind: .absolute, value: 20),
            PlannedSetLoadDraft(kind: .absolute, value: 60),
            PlannedSetLoadDraft(kind: .absolute, value: 100),
        ])
        XCTAssertEqual(sets.map(\.targetReps), [15, 7, 4])
        XCTAssertTrue(sets.allSatisfy { $0.lift == .squat })
    }

    // MARK: xN sets expansion

    func testWeightKgSlashRepsTimesNSetsExpandsToNIdenticalSets() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        155kg/5reps x3sets
        """)

        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.load == PlannedSetLoadDraft(kind: .absolute, value: 155) })
        XCTAssertTrue(sets.allSatisfy { $0.targetReps == 5 })
    }

    func testXNSetsExpansionToleratesTypoedRepsUnit() {
        // Real coach text has "x2reps" where "x2sets" was clearly meant.
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        130kg/5reps x2reps
        """)

        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertEqual(sets.count, 2)
        XCTAssertTrue(sets.allSatisfy { $0.load == PlannedSetLoadDraft(kind: .absolute, value: 130) && $0.targetReps == 5 })
    }

    func testXNSetsToleratesNoSpaceBeforeMultiplier() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Supino
        87,5kg/8repsx2sets
        """)

        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertEqual(sets.count, 2)
        XCTAssertTrue(sets.allSatisfy { $0.load == PlannedSetLoadDraft(kind: .absolute, value: 87.5) && $0.targetReps == 8 })
    }

    // MARK: RPE accessory expansion

    func testRPEShorthandExpandsToNIdenticalRPESets() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Cadeira extensora 4x12@9(RPE)
        """)

        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertEqual(sets.count, 4)
        XCTAssertTrue(sets.allSatisfy { $0.targetReps == 12 })
        XCTAssertTrue(sets.allSatisfy { $0.load == PlannedSetLoadDraft(kind: .rpe, value: 9) })
        XCTAssertTrue(sets.allSatisfy { $0.lift == .accessory })
        XCTAssertEqual(sets.first?.customExerciseName, "Cadeira extensora")
    }

    func testRPEShorthandTeleratesMissingOpenParen() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Cadeira Flexora
        4x12@9RPE)
        """)

        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertEqual(sets.count, 4)
        XCTAssertTrue(sets.allSatisfy { $0.load == PlannedSetLoadDraft(kind: .rpe, value: 9) })
    }

    func testRPEShorthandToleratesMissingRPEMarkerEntirely() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Rosca Direta barra W
        3x12@9
        """)

        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.load == PlannedSetLoadDraft(kind: .rpe, value: 9) })
        XCTAssertTrue(sets.allSatisfy { $0.targetReps == 12 })
    }

    // MARK: OFF/DESCANSO empty-day handling

    func testOffDescansoDayIsPreservedAsEmptyDayNotSkipped() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        100/5
        Dia 2) OFF/DESCANSO
        Dia 3)
        Supino
        100/5
        """)

        XCTAssertEqual(result.draft.days.count, 3)
        XCTAssertEqual(result.draft.days[1].sets.count, 0)
        XCTAssertEqual(result.draft.days[1].name, "Day 2")
        XCTAssertFalse(result.draft.days[0].sets.isEmpty)
        XCTAssertFalse(result.draft.days[2].sets.isEmpty)
    }

    func testOffAloneIsRecognizedAsRestDay() {
        let result = ProgramImportParser.parse("""
        Dia 1) OFF
        """)
        XCTAssertEqual(result.draft.days.first?.sets.count, 0)
    }

    func testDescansoAloneIsRecognizedAsRestDay() {
        let result = ProgramImportParser.parse("""
        Dia 1) DESCANSO
        """)
        XCTAssertEqual(result.draft.days.first?.sets.count, 0)
    }

    func testRestDayIsCaseInsensitive() {
        let result = ProgramImportParser.parse("""
        Dia 1) off/descanso
        """)
        XCTAssertEqual(result.draft.days.first?.sets.count, 0)
    }

    // MARK: Intervalo duration parsing

    func testIntervaloPlainSecondsAppliesToPrecedingSets() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Cadeira extensora 4x12@9(RPE)
        Intervalo: 90s
        """)
        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertTrue(sets.allSatisfy { $0.restSeconds == 90 })
    }

    func testIntervaloMinutesAppliesToPrecedingSets() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Cadeira extensora 4x12@9(RPE)
        Intervalo: 2mins
        """)
        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertTrue(sets.allSatisfy { $0.restSeconds == 120 })
    }

    func testIntervaloMinuteRangeUsesUpperBound() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        100/5
        Intervalo: 4-5mins
        """)
        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertTrue(sets.allSatisfy { $0.restSeconds == 300 })
    }

    func testIntervaloWithNoSpaceBeforeColonAndValue() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        100/5
        Intervalo:4-5mins
        """)
        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertTrue(sets.allSatisfy { $0.restSeconds == 300 })
    }

    func testIntervaloAppliesToNearestPrecedingExerciseNotAnEarlierOne() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        100/5
        Intervalo: 90s
        Supino
        80/5
        Intervalo: 2mins
        """)
        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertEqual(sets.first(where: { $0.lift == .squat })?.restSeconds, 90)
        XCTAssertEqual(sets.first(where: { $0.lift == .bench })?.restSeconds, 120)
    }

    func testMissingIntervaloLeavesDefaultRest() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        100/5
        """)
        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertEqual(sets.first?.restSeconds, 180)
    }

    func testMalformedIntervaloWithNoDurationIsPreservedAsNoteAndDoesNotCrash() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        4x12@9(RPE)/Intervalo:
        """)
        // No crash, sets still parsed, and the malformed duration surfaces as a note.
        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertEqual(sets.count, 4)
        XCTAssertTrue(result.notes.contains { $0.text.lowercased().contains("rest duration") })
    }

    // MARK: PT lift-name mapping

    func testAgachamentoMapsToSquat() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        100/5
        """)
        XCTAssertEqual(result.draft.days.first?.sets.first?.lift, .squat)
    }

    func testAgachamentoComPausaVariantMapsToSquat() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento com pausa
        100/5
        """)
        XCTAssertEqual(result.draft.days.first?.sets.first?.lift, .squat)
    }

    func testSupinoMapsToBench() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Supino
        80/5
        """)
        XCTAssertEqual(result.draft.days.first?.sets.first?.lift, .bench)
    }

    func testSupinoInclinadoVariantMapsToBench() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Supino Inclinado
        80/5
        """)
        XCTAssertEqual(result.draft.days.first?.sets.first?.lift, .bench)
    }

    func testSupinoFechadoVariantMapsToBench() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Supino fechado com pausa
        80/5
        """)
        XCTAssertEqual(result.draft.days.first?.sets.first?.lift, .bench)
    }

    func testLevantamentoTerraMapsToDeadlift() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Levantamento Terra
        150/1
        """)
        XCTAssertEqual(result.draft.days.first?.sets.first?.lift, .deadlift)
    }

    func testUnrecognizedExerciseNameFallsBackToAccessoryWithVerbatimName() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Tríceps Pulley 4x12@8(RPE)
        """)
        let set = try! XCTUnwrap(result.draft.days.first?.sets.first)
        XCTAssertEqual(set.lift, .accessory)
        XCTAssertEqual(set.customExerciseName, "Tríceps Pulley")
    }

    // MARK: Film reminder / free-text parenthetical notes

    func testFilmarParentheticalSetsFilmReminder() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento (Filmar)
        100/5
        """)
        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertTrue(sets.allSatisfy(\.filmReminder))
    }

    func testNonFilmarParentheticalIsKeptAsNoteNotDropped() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Levantamento Terra (Convencional)
        150/1
        """)
        let sets = try! XCTUnwrap(result.draft.days.first).sets
        XCTAssertFalse(sets.first?.filmReminder ?? true)
        XCTAssertTrue(result.notes.contains { $0.text == "Convencional" })
    }

    // MARK: Unrecognized-line preservation as notes

    func testUnrecognizedSetTokenIsPreservedAsNoteNotDropped() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        100/5, garbage-token
        """)
        XCTAssertTrue(result.notes.contains { $0.text.contains("garbage-token") })
        // The recognized token still parses fine alongside the bad one.
        XCTAssertEqual(result.draft.days.first?.sets.count, 1)
    }

    func testProgramLevelHeaderTextBeforeFirstDiaIsPreservedAsNote() {
        let result = ProgramImportParser.parse("""
        Programa semanal (Powerlifting )
        Atleta: Amadeu
        Dia 1)
        Agachamento
        100/5
        """)
        XCTAssertTrue(result.notes.contains { $0.dayIndex == nil && $0.text.contains("Atleta: Amadeu") })
    }

    // MARK: Mesociclo/Semana header extraction

    func testMesocicloAndSemanaAreExtractedFromHeader() {
        let result = ProgramImportParser.parse("""
        Mesociclo 2/Semana 6
        Dia 1)
        Agachamento
        100/5
        """)
        XCTAssertEqual(result.draft.mesocycleNumber, 2)
        XCTAssertEqual(result.draft.weekNumber, 6)
    }

    func testMesocicloAndSemanaAreNilWhenAbsent() {
        let result = ProgramImportParser.parse("""
        Dia 1)
        Agachamento
        100/5
        """)
        XCTAssertNil(result.draft.mesocycleNumber)
        XCTAssertNil(result.draft.weekNumber)
    }

    // MARK: Never crashes on garbage input

    func testEmptyStringDoesNotCrashAndProducesNoDays() {
        let result = ProgramImportParser.parse("")
        XCTAssertTrue(result.draft.days.isEmpty)
    }

    func testTextWithNoDayHeadersDoesNotCrash() {
        let result = ProgramImportParser.parse("just some random pasted text\nwith no structure at all")
        XCTAssertTrue(result.draft.days.isEmpty)
        XCTAssertFalse(result.notes.isEmpty)
    }

    // MARK: Golden fixture — exact spec sourcing-conversation block

    func testGoldenFixtureFromSpecSourcingConversation() {
        let text = """
        Programa semanal (Powerlifting )
        Atleta: Amadeu
        Mesociclo 2/Semana 6
        Dia 1)
        Agachamento (Filmar)
        20/15, 60/7, 100/4, 125/3, 140/2, 155kg/5reps x3sets
        Intervalo: 4-5mins
        Cadeira extensora 4x12@9(RPE) / Intervalo: 90s
        Cadeira Flexora
        4x12@9RPE)/ Intervalo :90s
        Panturrilha em pé máq.
        4x12@9(RPE)/Intervalo:
        Intervalo: 4-5mins
        Intervalo: 90s
        Dia 2)
        Supino com pausa (Filmar)
        20/10, 40/8, 55/5, 70/3, 87,5kg/8reps x3sets , 80/8 repsx2sets , 70kg/ 8reps
        Intervalo:4-5mins
        Supino Inclinado (filmar)
        20/10, 60/8, 70kg /8reps x2sets
        Intervalo: 4-5mins
        Remada aberta na máquina 4x10@8(RPE)/ Intervalo: 90s
        Tríceps Pulley 4x12@8(RPE)/Intervalo: 90s
        Rosca dumbbell (banco 45)
        4x12@8(RPE)Intervalo: 90s
        Dia 3) OFF/DESCANSO
        Dia 4)
        Levantamento Terra (Filmar) (Convencional)
        60/8, 100/5, 120/3, 135/2, 150/1, 175kg/7repsx2sets
        Agachamento com pausa
        20/10, 60/8,100/5,115/3,
        130kg/5reps x2reps
        Dia 5)
        Supino fechado com
        (pausa de 2s)
        20/10, 50/8, 60/5, 72,5kg/8repsx2sets
        Gravitron Aberto (Barra Fixa) 4x12@9(RPE)/ Intervalo : 90s
        Remada curvada aberta 4x10@9(RPE)/ Intervalo : 2mins
        Remada unilateral com halter
        3x8@9(RPE)/Intervalo :90s
        Rosca Direta barra W 3x12@9Intervalo: 60s
        Dia 6) OFF/DESCANSO
        Dia 7) OFF/DESCANSO
        """

        let result = ProgramImportParser.parse(text)
        let draft = result.draft

        // Mesocycle / week label.
        XCTAssertEqual(draft.mesocycleNumber, 2)
        XCTAssertEqual(draft.weekNumber, 6)

        // 7 days, faithfully numbered — Dia 3/6/7 are real empty rest days.
        XCTAssertEqual(draft.days.count, 7)
        XCTAssertEqual(draft.days.map(\.name), (1...7).map { "Day \($0)" })
        XCTAssertEqual(draft.days[2].sets.count, 0)
        XCTAssertEqual(draft.days[5].sets.count, 0)
        XCTAssertEqual(draft.days[6].sets.count, 0)

        // Day 1: Agachamento (8 sets), Cadeira extensora (4), Cadeira Flexora (4), Panturrilha (4).
        let day1 = draft.days[0].sets
        XCTAssertEqual(day1.count, 20)
        let day1Squat = day1.filter { $0.lift == .squat }
        XCTAssertEqual(day1Squat.count, 8)
        XCTAssertTrue(day1Squat.allSatisfy(\.filmReminder))
        XCTAssertEqual(day1Squat.map(\.restSeconds), Array(repeating: 300, count: 8))
        XCTAssertEqual(day1Squat.prefix(5).map(\.targetReps), [15, 7, 4, 3, 2])
        XCTAssertEqual(day1Squat.suffix(3).map(\.load), Array(repeating: PlannedSetLoadDraft(kind: .absolute, value: 155), count: 3))

        let day1Accessories = day1.filter { $0.lift == .accessory }
        XCTAssertEqual(day1Accessories.count, 12)
        let cadeiraExtensora = day1Accessories.filter { $0.customExerciseName == "Cadeira extensora" }
        XCTAssertEqual(cadeiraExtensora.count, 4)
        XCTAssertTrue(cadeiraExtensora.allSatisfy { $0.restSeconds == 90 && $0.targetReps == 12 && $0.load == PlannedSetLoadDraft(kind: .rpe, value: 9) })
        let cadeiraFlexora = day1Accessories.filter { $0.customExerciseName == "Cadeira Flexora" }
        XCTAssertEqual(cadeiraFlexora.count, 4)
        XCTAssertTrue(cadeiraFlexora.allSatisfy { $0.restSeconds == 90 })
        let panturrilha = day1Accessories.filter { $0.customExerciseName == "Panturrilha em pé máq." }
        XCTAssertEqual(panturrilha.count, 4)
        XCTAssertTrue(panturrilha.allSatisfy { $0.restSeconds == 90 })

        // Day 2: Supino com pausa (10), Supino Inclinado (4), Remada aberta (4), Tríceps Pulley (4), Rosca dumbbell (4).
        let day2 = draft.days[1].sets
        XCTAssertEqual(day2.count, 26)
        let day2Bench = day2.filter { $0.lift == .bench }
        XCTAssertEqual(day2Bench.count, 14)
        XCTAssertTrue(day2Bench.allSatisfy(\.filmReminder))
        let supinoComPausa = day2Bench.filter { $0.restSeconds == 300 }
        // Both bench exercises got a "4-5mins" Intervalo, so all 14 read 300s.
        XCTAssertEqual(supinoComPausa.count, 14)
        // Regression: the comma-decimal weight "87,5kg/8reps x3sets" must not
        // get mis-split by the blob-level comma tokenizer (87 / 5kg...).
        XCTAssertEqual(day2Bench.filter { $0.load == PlannedSetLoadDraft(kind: .absolute, value: 87.5) }.count, 3)
        XCTAssertTrue(day2Bench.filter { $0.load == PlannedSetLoadDraft(kind: .absolute, value: 87.5) }.allSatisfy { $0.targetReps == 8 })
        XCTAssertEqual(day2Bench.filter { $0.load == PlannedSetLoadDraft(kind: .absolute, value: 80) }.count, 2)

        let day2Accessories = day2.filter { $0.lift == .accessory }
        XCTAssertEqual(day2Accessories.count, 12)
        XCTAssertTrue(day2Accessories.allSatisfy { $0.restSeconds == 90 })
        let roscaDumbbell = day2Accessories.filter { $0.customExerciseName == "Rosca dumbbell" }
        XCTAssertEqual(roscaDumbbell.count, 4)

        // Day 3/6/7 already asserted empty above.

        // Day 4: Levantamento Terra (7), Agachamento com pausa (6).
        let day4 = draft.days[3].sets
        XCTAssertEqual(day4.count, 13)
        let deadlift = day4.filter { $0.lift == .deadlift }
        XCTAssertEqual(deadlift.count, 7)
        XCTAssertTrue(deadlift.allSatisfy(\.filmReminder))
        XCTAssertTrue(deadlift.allSatisfy { $0.restSeconds == 180 }) // no Intervalo in this block
        // "175kg/7repsx2sets" (no space before the multiplier) expands correctly.
        XCTAssertEqual(deadlift.filter { $0.load == PlannedSetLoadDraft(kind: .absolute, value: 175) && $0.targetReps == 7 }.count, 2)
        let squatDay4 = day4.filter { $0.lift == .squat }
        XCTAssertEqual(squatDay4.count, 6)
        XCTAssertTrue(squatDay4.allSatisfy { $0.restSeconds == 180 })
        // "130kg/5reps x2reps" — typo'd "x2reps" — still expands to 2 sets.
        XCTAssertEqual(squatDay4.filter { $0.load == PlannedSetLoadDraft(kind: .absolute, value: 130) && $0.targetReps == 5 }.count, 2)

        // Day 5: Supino fechado com (5), Gravitron Aberto (4), Remada curvada aberta (4),
        // Remada unilateral com halter (3), Rosca Direta barra W (3).
        let day5 = draft.days[4].sets
        XCTAssertEqual(day5.count, 19)
        let day5Bench = day5.filter { $0.lift == .bench }
        XCTAssertEqual(day5Bench.count, 5)
        XCTAssertTrue(day5Bench.allSatisfy { $0.restSeconds == 180 }) // no Intervalo reached this block
        // "72,5kg/8repsx2sets" — comma-decimal weight, no space before the multiplier.
        XCTAssertEqual(day5Bench.filter { $0.load == PlannedSetLoadDraft(kind: .absolute, value: 72.5) && $0.targetReps == 8 }.count, 2)
        let day5Accessories = day5.filter { $0.lift == .accessory }
        XCTAssertEqual(day5Accessories.count, 14)
        let gravitron = day5Accessories.filter { $0.customExerciseName == "Gravitron Aberto" }
        XCTAssertEqual(gravitron.count, 4)
        XCTAssertTrue(gravitron.allSatisfy { $0.restSeconds == 90 })
        let remadaCurvada = day5Accessories.filter { $0.customExerciseName == "Remada curvada aberta" }
        XCTAssertEqual(remadaCurvada.count, 4)
        XCTAssertTrue(remadaCurvada.allSatisfy { $0.restSeconds == 120 })
        let remadaUnilateral = day5Accessories.filter { $0.customExerciseName == "Remada unilateral com halter" }
        XCTAssertEqual(remadaUnilateral.count, 3)
        XCTAssertTrue(remadaUnilateral.allSatisfy { $0.restSeconds == 90 })
        let roscaDireta = day5Accessories.filter { $0.customExerciseName == "Rosca Direta barra W" }
        XCTAssertEqual(roscaDireta.count, 3)
        XCTAssertTrue(roscaDireta.allSatisfy { $0.restSeconds == 60 && $0.load == PlannedSetLoadDraft(kind: .rpe, value: 9) })

        // Free-text notes survive rather than being dropped.
        XCTAssertTrue(result.notes.contains { $0.text.contains("Atleta: Amadeu") })
        XCTAssertTrue(result.notes.contains { $0.text == "Convencional" })
        XCTAssertTrue(result.notes.contains { $0.text == "Barra Fixa" })
        XCTAssertTrue(result.notes.contains { $0.text == "banco 45" })
        XCTAssertTrue(result.notes.contains { $0.text == "pausa de 2s" })
    }
}
