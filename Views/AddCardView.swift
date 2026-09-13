//
//  AddCardView.swift
//  anki
//

import SwiftUI

/// Единая форма создания и редактирования карточки
struct AddCardView: View {

    let viewModel: CardViewModel
    private let card: CardDTO?
    private let onSave: (CardDTO) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var word: String
    @State private var translation: String
    @State private var examples: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case word, translation, examples
    }

    init(
        viewModel: CardViewModel,
        card: CardDTO? = nil,
        onSave: @escaping (CardDTO) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.card = card
        self.onSave = onSave
        _word = State(initialValue: card?.word ?? "")
        _translation = State(initialValue: card?.translation ?? "")
        _examples = State(initialValue: card?.examples ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    editor(
                        label: "СЛОВО ИЛИ ФРАЗА",
                        placeholder: "to look forward to",
                        text: $word,
                        field: .word
                    )
                    .rawTextInput()

                    editor(
                        label: "ПЕРЕВОД",
                        placeholder: "с нетерпением ждать",
                        text: $translation,
                        field: .translation
                    )

                    editor(
                        label: "ПРИМЕРЫ · НЕОБЯЗАТЕЛЬНО",
                        placeholder: "I'm looking forward to seeing you.",
                        text: $examples,
                        field: .examples,
                        lineLimit: 1...6
                    )

                    if let errorMessage {
                        errorBanner(errorMessage)
                    }

                    Text(helperText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Сообщение про дубликат перестаёт быть верным, как только слово изменили
            .onChange(of: word) { withAnimation(.snappy) { errorMessage = nil } }
            .safeAreaInset(edge: .bottom) { saveButton }
            .navigationTitle(card == nil ? "Новая карточка" : "Редактирование")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .task { focusedField = .word }
        }
    }

    // MARK: - Поля

    private func editor(
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        lineLimit: ClosedRange<Int> = 1...4
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(label)

            TextField(placeholder, text: text, axis: .vertical)
                .font(.system(.title3, design: .rounded, weight: .medium))
                .textFieldStyle(.plain)
                .lineLimit(lineLimit)
                .focused($focusedField, equals: field)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: 20)
        .contentShape(.rect(cornerRadius: 20))
        .onTapGesture { focusedField = field }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.red.opacity(0.1), in: .rect(cornerRadius: 14))
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var saveButton: some View {
        Button(action: save) {
            Text("Сохранить")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .disabled(!isValid || isSaving)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Сохранение

    private var isValid: Bool {
        !word.trimmed.isEmpty && !translation.trimmed.isEmpty
    }

    private var helperText: String {
        card == nil
            ? "Карточку можно будет повторить уже сегодня."
            : "Прогресс и дата следующего повторения не изменятся."
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                let savedCard: CardDTO
                if let card {
                    savedCard = try await viewModel.updateCard(
                        card,
                        word: word,
                        translation: translation,
                        examples: examples
                    )
                } else {
                    savedCard = try await viewModel.addCard(
                        word: word,
                        translation: translation,
                        examples: examples
                    )
                }
                onSave(savedCard)
                dismiss()
            } catch {
                withAnimation(.snappy) { errorMessage = error.localizedDescription }
                isSaving = false
            }
        }
    }
}

private extension String {

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG
#Preview {
    AddCardView(viewModel: .preview())
}
#endif
