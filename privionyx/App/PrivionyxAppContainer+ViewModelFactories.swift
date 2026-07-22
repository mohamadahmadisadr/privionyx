import Foundation

extension PrivionyxAppContainer {
    @MainActor
    func makeAddReceiptViewModel(appState: PrivionyxAppState, initialDraft: ReceiptDraft? = nil) -> AddReceiptViewModel {
        AddReceiptViewModel(
            appState: appState,
            imageProcessor: imageProcessor,
            perspectiveService: perspectiveService,
            processReceiptUseCase: processReceiptUseCase,
            merchantRules: merchantRuleService,
            initialDraft: initialDraft
        )
    }
}
