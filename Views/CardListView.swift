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
    /// Строка, у которой сейчас раскрыта кнопка удаления. Открыта всегда одна
    @State private var swipedCardID: CardDTO.ID?

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
                        isSwiped: swipedCardID == card.id,
                        onOpen: {
                            swipedCardID = nil
                            selectedCard = card
                        },
                        onReveal: { swipedCardID = card.id },
                        onClose: { if swipedCardID == card.id { swipedCardID = nil } },
                        onDelete: {
                            swipedCardID = nil
                            Task { await viewModel.delete(card) }
                        }
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
/// Свайп сделан вручную, потому что системный `swipeActions` в iOS 26 рисует
/// маленькую круглую кнопку, а нужна красная область во всю высоту строки
private struct CardRow: View {

    let card: CardDTO
    let isSwiped: Bool
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var dragTranslation: CGFloat = 0

    /// Ширина кнопки удаления в раскрытом состоянии
    private static let buttonWidth: CGFloat = 88

    /// Смещение, после которого отпускание удаляет карточку без нажатия на корзину
    private static let fullSwipeDistance: CGFloat = 200

    /// Дальше тащить нет смысла — порог уже пройден.
    private static let maximumOffset: CGFloat = fullSwipeDistance + 120

    /// Порог пройден: подсказываем это тем, что корзина уезжает к краю строки
    private var isPastFullSwipe: Bool {
        -offset >= Self.fullSwipeDistance
    }

    private var offset: CGFloat {
        let base = isSwiped ? -Self.buttonWidth : 0
        return min(0, max(-Self.maximumOffset, base + dragTranslation))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteButton
            rowContent.offset(x: offset)
        }
        .animation(.snappy(duration: 0.28), value: isSwiped)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityAction(named: "Удалить") { onDelete() }
    }

    /// Красная область ровно по высоте строки: она и есть открывающийся зазор
    private var deleteButton: some View {
        Button(action: onDelete) {
            Color.red
                .overlay(alignment: isPastFullSwipe ? .leading : .center) {
                    Image(systemName: "trash")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: Self.buttonWidth)
                }
        }
        .buttonStyle(.plain)
        .frame(width: max(0, -offset))
        .clipped()
        .accessibilityHidden(true)
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
        .overlay { gestureLayer }
    }

    @ViewBuilder
    private var gestureLayer: some View {
        #if os(iOS)
        RowGestureLayer(
            onPanChanged: { dragTranslation = $0 },
            onPanEnded: { translation in
                let total = (isSwiped ? -Self.buttonWidth : 0) + translation

                withAnimation(.snappy(duration: 0.28)) {
                    dragTranslation = 0
                    if total < -Self.fullSwipeDistance {
                        onDelete()
                    } else if total < -Self.buttonWidth / 2 {
                        onReveal()
                    } else {
                        onClose()
                    }
                }
            },
            onTap: { isSwiped ? onClose() : onOpen() }
        )
        #else
        Color.clear
            .contentShape(.rect)
            .onTapGesture { isSwiped ? onClose() : onOpen() }
        #endif
    }
}


#if os(iOS)
/// Жесты строки списка на распознавателях UIKit
///
/// SwiftUI-жест `DragGesture` внутри `List` забирает касание целиком: если палец
/// пошёл дугой — сначала чуть вбок, потом вверх, — список переставал
/// прокручиваться до конца жеста. UIKit-распознаватель умеет отказаться от
/// касания в самом начале, и вертикальное движение остаётся списку
private struct RowGestureLayer: UIViewRepresentable {

    var onPanChanged: (CGFloat) -> Void
    var onPanEnded: (CGFloat) -> Void
    var onTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Замыкания захватывают состояние строки, поэтому обновляем их каждый раз
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var parent: RowGestureLayer

        init(parent: RowGestureLayer) {
            self.parent = parent
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view).x

            switch recognizer.state {
            case .changed:
                parent.onPanChanged(translation)
            case .ended, .cancelled, .failed:
                parent.onPanEnded(translation)
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            parent.onTap()
        }

        /// Берём жест, только если он начался как горизонтальный
        /// Всё остальное — прокрутка списка, и мы в неё не вмешиваемся
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
#endif

#if DEBUG
#Preview("Список") {
    CardListView(viewModel: .preview())
}

#Preview("Пустой список") {
    CardListView(viewModel: .preview(seeded: false))
}
#endif
