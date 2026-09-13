//
//  ankiApp.swift
//  anki
//
//  Created by Александр  Ерусланов on 07.09.2026
//

import SwiftData
import SwiftUI

@main
struct ankiApp: App {

    /// Хранилище приложения.
    private let modelContainer: ModelContainer

    /// Общая модель для всех экранов: список, добавление, повторение
    @State private var viewModel: CardViewModel

    init() {
        let container = ModelContainer.ankiContainer()
        self.modelContainer = container
        _viewModel = State(initialValue: CardViewModel(dataController: DataController(modelContainer: container)))
    }

    var body: some Scene {
        WindowGroup {
            CardListView(viewModel: viewModel)
        }
        .modelContainer(modelContainer)
    }
}
