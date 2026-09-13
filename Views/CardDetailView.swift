//
//  CardDetailView.swift
//  anki
//

import SwiftUI

/// Экран повторения: перевод открывается нажатием, ответ — свайпом
///
/// Вправо — «Знаю», влево — «Не знаю»
struct CardDetailView: View {

    let viewModel: CardViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Подсказку про направление свайпов показываем до первого ответа,
    /// дальше она больше не нужна
    @AppStorage("hasAnsweredFirstCard") private var hasAnsweredFirstCard = false

    @State private var card: CardDTO
    @State private var isRevealed = false
    @State private var isSubmitting = false
    @State private var isEditingCard = false
    @State private var dragOffset: CGSize = .zero

    /// Смещение, после которого свайп считается ответом
    private let decisionThreshold: CGFloat = 110

    init(card: CardDTO, viewModel: CardViewModel) {
        self.viewModel = viewModel
        _card = State(initialValue: card)
    }

    var body: some View {
        VStack(spacing: 16) {
            flashcard
                .frame(maxHeight: 560)
            flipButton
            statusChips

            if !hasAnsweredFirstCard {
                swipeHint
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .navigationTitle("Повторение")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isEditingCard = true
                } label: {
                    Label("Редактировать карточку", systemImage: "pencil")
                }
                .disabled(isSubmitting)
            }
        }
        .sheet(isPresented: $isEditingCard) {
            AddCardView(viewModel: viewModel, card: card) { updatedCard in
                card = updatedCard
            }
        }
        .sensoryFeedback(.selection, trigger: isRevealed)
        .sensoryFeedback(.impact, trigger: card.id)
    }

    // MARK: - Карточка

    private var flashcard: some View {
        ZStack {
            face(
                label: "СЛОВО",
                text: card.word,
                font: .system(.largeTitle, design: .rounded, weight: .bold)
            )
            .opacity(isRevealed ? 0 : 1)

            face(
                label: "ПЕРЕВОД",
                text: card.translation,
                font: .system(.title, design: .rounded, weight: .semibold),
                examples: card.examples
            )
            .opacity(isRevealed ? 1 : 0)
            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(isRevealed ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .overlay(alignment: .top) { decisionBadge }
        .offset(dragOffset)
        .rotationEffect(.degrees(dragOffset.width / 26))
        .contentShape(.rect(cornerRadius: 32))
        .onTapGesture(perform: flip)
        .gesture(swipeGesture)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isRevealed ? "Показать слово" : "Показать перевод")
        .accessibilityAction(named: "Знаю") { answer(remembered: true) }
        .accessibilityAction(named: "Не знаю") { answer(remembered: false) }
    }

    private func face(label: String, text: String, font: Font, examples: String? = nil) -> some View {
        VStack(spacing: 16) {
            FieldLabel(label)
            Text(text)
                .font(font)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)

            if let examples, !examples.isEmpty {
                Divider()
                    .padding(.horizontal, 32)

                Text(examples)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(6)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
        .cardSurface(cornerRadius: 32)
    }

    private var flipButton: some View {
        Button(action: flip) {
            Text(isRevealed ? "Скрыть перевод" : "Показать перевод")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 4)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }

    // MARK: - Свайпы

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isSubmitting else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isSubmitting else { return }
                // Учитываем инерцию: короткий резкий взмах тоже засчитывается
                switch decision(for: value.predictedEndTranslation) {
                case .known: answer(remembered: true)
                case .unknown: answer(remembered: false)
                case nil: returnCardToCenter()
                }
            }
    }

    private enum SwipeDecision {
        case known, unknown
    }

    /// Какое действие соответствует смещению карточки:
    /// вправо — «Знаю», влево — «Не знаю»
    private func decision(for translation: CGSize) -> SwipeDecision? {
        let horizontal = translation.width
        guard abs(horizontal) > decisionThreshold else { return nil }
        return horizontal > 0 ? .known : .unknown
    }

    /// Подсказка поверх карточки во время свайпа — она же заменяет кнопки
    @ViewBuilder
    private var decisionBadge: some View {
        if let decision = decision(for: scaledUpDragOffset) {
            let progress = min(1, badgeProgress(for: decision))

            switch decision {
            case .known:
                badge("ЗНАЮ", tint: .green, angle: -8, progress: progress)
            case .unknown:
                badge("НЕ ЗНАЮ", tint: .red, angle: 8, progress: progress)
            }
        }
    }

    /// Значок появляется раньше, чем свайп достигает порога
    private var scaledUpDragOffset: CGSize {
        CGSize(width: dragOffset.width * 2.2, height: dragOffset.height * 2.2)
    }

    private func badgeProgress(for decision: SwipeDecision) -> Double {
        Double(abs(dragOffset.width)) / Double(decisionThreshold)
    }

    /// Разовая подсказка новичку: какой свайп что означает
    private var swipeHint: some View {
        Text("Смахните вправо, если знаете, и влево, если нет")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 2)
            .transition(.opacity)
    }

    private func badge(_ title: String, tint: Color, angle: Double, progress: Double) -> some View {
        Text(title)
            .font(.caption.weight(.heavy))
            .tracking(1.2)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(tint, in: .capsule)
            .rotationEffect(.degrees(angle))
            .opacity(progress)
            .scaleEffect(0.85 + 0.15 * progress)
            .padding(.top, 24)
    }

    // MARK: - Статистика и подсказка

    private var statusChips: some View {
        HStack(spacing: 8) {
            chip(card.repetitionsText, systemImage: "checkmark.seal")
            chip(card.intervalText, systemImage: "timer")
            // При крупных шрифтах три чипа в строку уже не помещаются
            if !dynamicTypeSize.isAccessibilitySize {
                chip(card.nextReviewDateShortText, systemImage: "calendar")
            }
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .cardSurface(cornerRadius: 14)
    }

    // MARK: - Действия

    private func flip() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            isRevealed.toggle()
        }
    }

    private func returnCardToCenter() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            dragOffset = .zero
        }
    }

    /// Сохраняет ответ и сразу показывает следующую карточку, которую пора
    /// повторить. Когда таких больше нет — сессия закончена, возвращаемся к списку
    private func answer(remembered: Bool) {
        guard !isSubmitting else { return }
        isSubmitting = true
        let answered = card

        withAnimation(.easeOut(duration: 0.25)) {
            dragOffset = CGSize(width: remembered ? 800 : -800, height: 60)
            hasAnsweredFirstCard = true
        } completion: {
            Task {
                await viewModel.review(answered, remembered: remembered)

                guard let next = viewModel.randomDueCard(excluding: answered) else {
                    dismiss()
                    return
                }

                show(next)
                isSubmitting = false
            }
        }
    }

    /// Выкладывает следующую карточку: она въезжает снизу, переводом вниз
    private func show(_ next: CardDTO) {
        card = next
        isRevealed = false
        dragOffset = CGSize(width: 0, height: 500)

        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            dragOffset = .zero
        }
    }
}

#if DEBUG
#Preview {
    let sample = CardViewModel.previewCard()

    NavigationStack {
        CardDetailView(card: sample.card, viewModel: sample.viewModel)
    }
}
#endif
