//
//  CardViewModel.swift
//  anki
//

import Foundation
import Observation
import SwiftData

/// Состояние экранов карточек.
///
/// Живёт на главном потоке и хранит только снимки ``CardDTO``;
/// вся работа с базой уходит в фоновый актор ``DataController``
@Observable
@MainActor
final class CardViewModel {

    /// Карточки, отсортированные по дате следующего повторения
    private(set) var cards: [CardDTO] = []

    /// Идёт первая загрузка списка.
    private(set) var isLoading = false

    /// Текст ошибки для алерта; `nil` — ошибки нет
    var errorMessage: String?

    /// Запрос поиска. Ищем только по слову — перевод специально не трогаем,
    /// иначе в списке всплывёт то, что нужно вспоминать
    var searchText = ""

    private let dataController: DataController

    init(dataController: DataController) {
        self.dataController = dataController
    }

    /// Карточки с учётом поиска
    var visibleCards: [CardDTO] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return cards }
        return cards.filter { $0.word.localizedCaseInsensitiveContains(query) }
    }

    /// Идёт ли сейчас поиск
    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Сколько карточек пора повторить прямо сейчас
    var dueCount: Int {
        cards.count { $0.isDue() }
    }

    /// Привязка для `.alert(_:isPresented:)`
    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    /// Перечитывает список из хранилища
    func loadCards() async {
        isLoading = true
        defer { isLoading = false }
        do {
            cards = try await dataController.cards()
        } catch {
            present(error)
        }
    }

    /// Добавляет карточку
    ///
    /// Ошибку не проглатывает, а пробрасывает: форма добавления показывает её сама,
    /// потому что алерт списка перекрыт модальным экраном
    @discardableResult
    func addCard(word: String, translation: String, examples: String?) async throws -> CardDTO {
        let card = try await dataController.addCard(word: word, translation: translation, examples: examples)
        await loadCards()
        return card
    }

    /// Обновляет текст карточки, оставляя историю повторений без изменений
    ///
    /// Как и при добавлении, форма сама показывает ошибку поверх модального экрана
    @discardableResult
    func updateCard(
        _ card: CardDTO,
        word: String,
        translation: String,
        examples: String?
    ) async throws -> CardDTO {
        let updatedCard = try await dataController.updateCard(
            id: card.id,
            word: word,
            translation: translation,
            examples: examples
        )
        await loadCards()
        return updatedCard
    }

    /// Удаляет карточку (свайп влево по строке)
    func delete(_ card: CardDTO) async {
        // Сначала убираем из списка, чтобы анимация не ждала базу
        cards.removeAll { $0.id == card.id }
        do {
            try await dataController.deleteCard(id: card.id)
        } catch {
            present(error)
            await loadCards()
        }
    }

    /// Случайная карточка, которую пора повторить, — для продолжения после ответа
    func randomDueCard(excluding card: CardDTO) -> CardDTO? {
        cards.filter { $0.id != card.id && $0.isDue() }.randomElement()
    }

    /// Отмечает результат повторения: `remembered` — свайп вправо, «Знаю»
    func review(_ card: CardDTO, remembered: Bool) async {
        do {
            try await dataController.review(id: card.id, remembered: remembered)
            await loadCards()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

#if DEBUG
extension CardViewModel {

    /// Модель с временным хранилищем в памяти — для превью Xcode
    static func preview(seeded: Bool = true) -> CardViewModel {
        let container = ModelContainer.ankiContainer(inMemory: true)
        if seeded {
            let context = container.mainContext
            for card in Card.samples {
                context.insert(card)
            }
            try? context.save()
        }
        return CardViewModel(dataController: DataController(modelContainer: container))
    }

    /// Модель и одна карточка из примеров — для превью экрана повторения
    static func previewCard() -> (viewModel: CardViewModel, card: CardDTO) {
        let container = ModelContainer.ankiContainer(inMemory: true)
        let card = Card.samples[0]
        container.mainContext.insert(card)
        try? container.mainContext.save()
        return (CardViewModel(dataController: DataController(modelContainer: container)), CardDTO(card))
    }
}
#endif
