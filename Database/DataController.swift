//
//  DataController.swift
//  anki
//

import Foundation
import SwiftData

/// Ошибки, которые может вернуть слой данных
nonisolated enum CardError: LocalizedError, Equatable {
    case emptyWord
    case emptyTranslation
    case duplicateWord(String)
    case cardNotFound

    var errorDescription: String? {
        switch self {
        case .emptyWord:
            return "Слово не может быть пустым."
        case .emptyTranslation:
            return "Добавьте перевод — без него карточку не повторить."
        case .duplicateWord(let word):
            return "Карточка «\(word)» уже есть в списке."
        case .cardNotFound:
            return "Карточка не найдена: возможно, она уже удалена."
        }
    }
}

/// Единственная точка доступа к SwiftData
///
/// `@ModelActor` создаёт актору собственный `ModelContext` и исполнитель,
/// поэтому все чтения и записи идут вне главного потока. Наружу отдаются
/// только `Sendable`-снимки ``CardDTO``
@ModelActor
actor DataController {

    /// Все карточки: сначала самые срочные, при равенстве — старые
    func cards() throws -> [CardDTO] {
        let descriptor = FetchDescriptor<Card>(
            sortBy: [
                SortDescriptor(\Card.nextReviewDate, order: .forward),
                SortDescriptor(\Card.createdAt, order: .forward)
            ]
        )
        return try modelContext.fetch(descriptor).map(CardDTO.init)
    }

    /// Создаёт карточку, проверив, что слово не пустое и не повторяется
    @discardableResult
    func addCard(word: String, translation: String, examples: String? = nil) throws -> CardDTO {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        let examples = examples?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !word.isEmpty else { throw CardError.emptyWord }
        guard !translation.isEmpty else { throw CardError.emptyTranslation }
        if try cardExists(word: word) { throw CardError.duplicateWord(word) }

        let card = Card(
            word: word,
            translation: translation,
            examples: (examples?.isEmpty ?? true) ? nil : examples
        )
        modelContext.insert(card)
        try modelContext.save()
        return CardDTO(card)
    }

    /// Обновляет текст карточки, не меняя прогресс и срок следующего повторения
    @discardableResult
    func updateCard(
        id: PersistentIdentifier,
        word: String,
        translation: String,
        examples: String? = nil
    ) throws -> CardDTO {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        let examples = examples?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !word.isEmpty else { throw CardError.emptyWord }
        guard !translation.isEmpty else { throw CardError.emptyTranslation }

        let card = try card(with: id)
        if word != card.word, try cardExists(word: word) {
            throw CardError.duplicateWord(word)
        }

        card.word = word
        card.translation = translation
        card.examples = (examples?.isEmpty ?? true) ? nil : examples
        try modelContext.save()
        return CardDTO(card)
    }

    /// Удаляет карточку по идентификатору
    func deleteCard(id: PersistentIdentifier) throws {
        let card = try card(with: id)
        modelContext.delete(card)
        try modelContext.save()
    }

    /// Отмечает результат повторения и пересчитывает интервал
    @discardableResult
    func review(id: PersistentIdentifier, remembered: Bool) throws -> CardDTO {
        let card = try card(with: id)
        if remembered {
            card.markAsKnown()
        } else {
            card.markAsUnknown()
        }
        try modelContext.save()
        return CardDTO(card)
    }

    /// Карточка по идентификатору
    ///
    /// Именно выборка, а не подписка `self[id, as:]`: для уже удалённой карточки
    /// та возвращает не `nil`, а нерабочий объект, и сохранение падает
    private func card(with id: PersistentIdentifier) throws -> Card {
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate<Card> { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        guard let card = try modelContext.fetch(descriptor).first else { throw CardError.cardNotFound }
        return card
    }

    /// Проверка уникальности слова до вставки: ограничение `.unique`
    /// молча перезаписало бы существующую карточку.
    private func cardExists(word: String) throws -> Bool {
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate<Card> { $0.word == word })
        descriptor.fetchLimit = 1
        return try modelContext.fetchCount(descriptor) > 0
    }
}

// MARK: - Хранилище

nonisolated extension ModelContainer {

    /// Контейнер приложения. `inMemory` используется в превью и тестах
    static func ankiContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([Card.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Не удалось создать хранилище SwiftData: \(error)")
        }
    }
}
