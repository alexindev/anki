//
//  Card.swift
//  anki
//

import Foundation
import SwiftData

/// Карточка для запоминания: слово или фраза, её перевод и состояние повторений
///
/// Тип помечен `nonisolated`: в проекте включена изоляция по умолчанию
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), а с моделью работает
/// фоновый актор ``DataController``, а не главный поток
@Model
nonisolated final class Card {

    /// Слово или фраза. Уникально в пределах хранилища и не может быть пустым
    @Attribute(.unique) var word: String

    /// Перевод слова или фразы
    var translation: String

    /// Примеры употребления — необязательное поле
    var examples: String?

    /// Дата создания карточки
    var createdAt: Date

    /// Дата следующего повторения: по ней сортируется список
    var nextReviewDate: Date

    /// Текущий интервал повторения в днях
    var interval: Int

    /// Количество успешных повторений подряд
    var repetitions: Int

    init(
        word: String,
        translation: String,
        examples: String? = nil,
        createdAt: Date = .now,
        nextReviewDate: Date? = nil,
        interval: Int = Card.minimumInterval,
        repetitions: Int = 0
    ) {
        self.word = word
        self.translation = translation
        self.examples = examples
        self.createdAt = createdAt
        // При создании карточка сразу доступна для повторения
        self.nextReviewDate = nextReviewDate ?? createdAt
        self.interval = interval
        self.repetitions = repetitions
    }
}

// MARK: - Интервальные повторения (упрощённый SM-2)

nonisolated extension Card {

    /// Минимальный интервал — один день
    static let minimumInterval = 1

    /// Интервал не растёт бесконечно: потолок — год
    static let maximumInterval = 365

    /// «Знаю»: повторений становится больше, интервал удваивается
    func markAsKnown(at date: Date = .now, calendar: Calendar = .current) {
        repetitions += 1
        interval = min(interval * 2, Card.maximumInterval)
        nextReviewDate = Card.reviewDate(inDays: interval, from: date, calendar: calendar)
    }

    /// «Не знаю»: прогресс сбрасывается, карточка возвращается на завтра
    func markAsUnknown(at date: Date = .now, calendar: Calendar = .current) {
        repetitions = 0
        interval = Card.minimumInterval
        nextReviewDate = Card.reviewDate(inDays: Card.minimumInterval, from: date, calendar: calendar)
    }

    /// Начало дня через `days` суток: карточка становится доступной с полуночи
    private static func reviewDate(inDays days: Int, from date: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: days, to: startOfToday)
            ?? date.addingTimeInterval(TimeInterval(days) * 24 * 60 * 60)
    }
}

#if DEBUG
nonisolated extension Card {

    /// Примеры для превью Xcode
    static var samples: [Card] {
        [
            Card(
                word: "serendipity",
                translation: "счастливая случайность",
                examples: "Finding this cafe was pure serendipity."
            ),
            Card(
                word: "to look forward to",
                translation: "с нетерпением ждать чего-либо",
                nextReviewDate: Calendar.current.date(byAdding: .day, value: 2, to: .now),
                interval: 4,
                repetitions: 2
            ),
            Card(word: "однажды", translation: "once", nextReviewDate: .now.addingTimeInterval(-86_400))
        ]
    }
}
#endif
