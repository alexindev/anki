//
//  CardListView.swift
//  anki
//

import SwiftUI

/// Главный экран: список карточек, самые срочные — сверху
struct CardListView: View {

    @Bindable var viewModel: CardViewModel

    @Environment(\.scenePhase) private var scenePhase

    @State private var isAddingCard = false
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var selectedCard: CardDTO?

    var body: some View {
        NavigationStack {
            content
                .safeAreaInset(edge: .top) {
                    if isSearchExpanded {
                        searchBar
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .navigationTitle("Карточки")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        searchControls
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isAddingCard = true
                        } label: {
                            Label("Добавить карточку", systemImage: "plus")
                        }
                    }
                }
                .navigationDestination(item: $selectedCard) { card in
                    CardDetailView(card: card, viewModel: viewModel)
                }
                .sheet(isPresented: $isAddingCard) {
                    AddCardView(viewModel: viewModel)
                }
                .alert("Не получилось", isPresented: $viewModel.isShowingError) {
                    Button("Понятно", role: .cancel) { }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
        }
        .task { await viewModel.loadCards() }
        .onChange(of: scenePhase) { _, phase in
            // Пока приложение было в фоне, мог смениться день:
            // «Завтра» должно стать «Повторить», а счётчик — пересчитаться
            guard phase == .active else { return }
            Task { await viewModel.loadCards() }
        }
    }

    /// Кнопка поиска рядом с «плюсом»
    private var searchControls: some View {
        Button {
            toggleSearch()
        } label: {
            Label(
                isSearchExpanded ? "Закрыть поиск" : "Поиск",
                systemImage: isSearchExpanded ? "xmark" : "magnifyingglass"
            )
        }
    }

    /// Строка поиска: выезжает из-под кнопки справа налево
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Поиск по слову", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .rawTextInput()

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Белая капсула на сером фоне списка — как строки карточек
        .background(.background, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        // Фокус ставим по появлению: до вставки в иерархию он не сработает
        .onAppear { isSearchFocused = true }
    }

    private func toggleSearch() {
        withAnimation(.snappy(duration: 0.3)) {
            isSearchExpanded.toggle()
            if !isSearchExpanded {
                viewModel.searchText = ""
                isSearchFocused = false
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.cards.isEmpty {
            emptyState
        } else if viewModel.visibleCards.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(viewModel.visibleCards) { card in
                    CardRow(
                        card: card,
                        onOpen: { selectedCard = card },
                        onDelete: { Task { await viewModel.delete(card) } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            } header: {
                Text(headerText)
            } footer: {
                Text("Смахните карточку влево, чтобы удалить.")
            }
        }
        .animation(.snappy(duration: 0.28), value: viewModel.visibleCards)
        .refreshable { await viewModel.loadCards() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            Text("Пока пусто")
                .font(.title2.weight(.semibold))

            Text("Добавьте слово или фразу — и начнём повторять.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                isAddingCard = true
            } label: {
                Label("Добавить карточку", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 10)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// «Всего» показываем всегда. Второй частью — либо найденное при поиске,
    /// либо количество срочных карточек, если они есть
    private var headerText: String {
        var parts = ["Всего: \(viewModel.cards.count)"]

        if viewModel.isSearching {
            parts.append("Найдено: \(viewModel.visibleCards.count)")
        } else if viewModel.dueCount > 0 {
            parts.append("К повторению: \(viewModel.dueCount)")
        }

        return parts.joined(separator: " · ")
    }
}

/// Строка списка: только слово и срок повторения
///
/// Перевод намеренно скрыт: если он виден в списке, повторение теряет смысл.
/// Системные swipeActions рисуют кнопку с отступами и растягивают её
/// при длинном свайпе, сохраняя стандартные жесты и анимацию удаления iOS.
private struct CardRow: View {

    let card: CardDTO
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            rowContent
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Удалить", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.word)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Image(systemName: card.isDue() ? "bolt.fill" : "clock")
                    Text(card.reviewStatusText())
                    if card.repetitions > 0 {
                        Text("· повторений: \(card.repetitions)")
                    }
                }
                .font(.caption)
                .foregroundStyle(card.isDue() ? Color.accentColor : Color.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

#if DEBUG
#Preview("Список") {
    CardListView(viewModel: .preview())
}

#Preview("Пустой список") {
    CardListView(viewModel: .preview(seeded: false))
}
#endif
