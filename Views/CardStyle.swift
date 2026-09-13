//
//  CardStyle.swift
//  anki
//

import SwiftUI

/// Мелкая подпись над содержимым карточки: «СЛОВО», «ПЕРЕВОД»
struct FieldLabel: View {

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

extension View {

    /// Компактный заголовок там, где он поддерживается (iOS)
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }

    /// Ввод как есть: без автозамены и заглавных букв
    func rawTextInput() -> some View {
        #if os(iOS)
        return autocorrectionDisabled().textInputAutocapitalization(.never)
        #else
        return autocorrectionDisabled()
        #endif
    }

    /// Спокойная подложка карточки или поля ввода
    func cardSurface(cornerRadius: CGFloat = 24) -> some View {
        background(.background.secondary, in: .rect(cornerRadius: cornerRadius))
    }
}
