//
//  CardDTO.swift
//  anki
//

import Foundation
import SwiftData

/// Снимок карточки для UI
///
/// Модели SwiftData привязаны к своему `ModelContext` и не являются `Sendable`,
/// поэтому фоновый ``DataController`` отдаёт наружу именно снимки
nonisolated struct CardDTO: Identifiable, Hashable, Sendable {
    let id: PersistentIdentifier
    let word: String
    let translation: String
    let examples: String?
    let createdAt: Date
    let nextReviewDate: Date
    let interval: Int
    let repetitions: Int

    init(_ card: Card) {
        self.id = card.persistentModelID
        self.word = card.word
        self.translation = card.translation
        self.examples = card.examples
        self.createdAt = card.createdAt
        self.nextReviewDate = card.nextReviewDate
        self.interval = card.interval
        self.repetitions = card.repetitions
    }
}

// MARK: - Представление для интерфейса

nonisolated extension CardDTO {

    /// Карточку пора повторять.
    func isDue(at date: Date = .now) -> Bool {
        nextReviewDate <= date
    }

    /// Сколько дней осталось до повторения: 0 — сегодня, отрицательное — просрочено
    func daysUntilReview(from date: Date = .now, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: date)
        let due = calendar.startOfDay(for: nextReviewDate)
        return calendar.dateComponents([.day], from: today, to: due).day ?? 0
    }

    /// Короткая подпись о сроке повторения: «Повторить», «Завтра», «Через 3 дня»
    func reviewStatusText(from date: Date = .now, calendar: Calendar = .current) -> String {
        let days = daysUntilReview(from: date, calendar: calendar)
        switch days {
        case ..<0: return "Просрочено"
        case 0: return "Повторить"
        case 1: return "Завтра"
        default: return "Через \(days) \(Self.dayWord(for: days))"
        }
    }

    /// Дата следующего повторения по-русски: «5 сентября 2026 г.»
    ///
    /// Локаль задана явно: интерфейс русский, а система у пользователя
    /// может быть на другом языке
    var nextReviewDateText: String {
        nextReviewDate.formatted(
            Date.FormatStyle(date: .long, time: .omitted).locale(Locale(identifier: "ru_RU"))
        )
    }

    /// Короткая дата повторения для компактных подписей: «5 сент.»
    var nextReviewDateShortText: String {
        nextReviewDate.formatted(
            Date.FormatStyle().day().month(.abbreviated).locale(Locale(identifier: "ru_RU"))
        )
    }

    /// Интервал в днях словами: «4 дня»
    var intervalText: String {
        "\(interval) \(Self.dayWord(for: interval))"
    }

    /// Короткая сводка состояния карточки для подзаголовка экрана
    var statusSummary: String {
        "\(repetitionsText) · интервал \(intervalText) · \(nextReviewDateShortText)"
    }

    /// Успешные повторения словами: «3 повторения»
    var repetitionsText: String {
        "\(repetitions) \(Self.repetitionWord(for: repetitions))"
    }

    /// Каким станет интервал, если нажать «Знаю»
    var intervalAfterKnown: Int {
        min(interval * 2, Card.maximumInterval)
    }

    /// Подпись на кнопке «Знаю»: «через 4 дня»
    var knownOutcomeText: String {
        "через \(intervalAfterKnown) \(Self.dayWord(for: intervalAfterKnown))"
    }

    /// Подпись на кнопке «Не знаю»
    var unknownOutcomeText: String {
        "завтра"
    }

    /// Склонение слова «повторение» для русского языка
    static func repetitionWord(for count: Int) -> String {
        let count = abs(count)
        if (11...14).contains(count % 100) { return "повторений" }
        switch count % 10 {
        case 1: return "повторение"
        case 2...4: return "повторения"
        default: return "повторений"
        }
    }

    /// Склонение слова «день» для русского языка
    static func dayWord(for count: Int) -> String {
        let count = abs(count)
        let remainder100 = count % 100
        let remainder10 = count % 10
        if (11...14).contains(remainder100) { return "дней" }
        switch remainder10 {
        case 1: return "день"
        case 2...4: return "дня"
        default: return "дней"
        }
    }
}
