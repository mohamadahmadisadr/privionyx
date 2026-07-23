import SwiftUI

struct AssistantView: View {
    @State private var viewModel: AssistantViewModel
    @AppStorage(AssistantBackend.storageKey) private var backend: AssistantBackend = .fallback
    @FocusState private var isComposerFocused: Bool

    init(appState: PrivionyxAppState) {
        _viewModel = State(initialValue: AssistantViewModel(appState: appState))
    }

    var body: some View {
        ZStack {
            PrivionyxTheme.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                if let notice = viewModel.fallbackNotice {
                    noticeBanner(notice)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                transcript

                if viewModel.suggestions.isEmpty == false {
                    suggestionRow
                        .padding(.bottom, 10)
                }

                composer
                    .padding(.horizontal, 16)
                    .padding(.bottom, PrivionyxTheme.Metrics.tabBarClearance)
            }
            .padding(.top, 8)
        }
        .task(id: backend) {
            await viewModel.prepare(backend: backend)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.accent)
                .frame(width: 34, height: 34)
                .background(PrivionyxTheme.Colors.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("AI Assistant")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                Text("Understands every receipt you scan")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
            }

            Spacer()
        }
    }

    private func noticeBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .privionyxGlass(cornerRadius: 12)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }

                    if viewModel.isResponding {
                        TypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(Self.typingIndicatorID)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .contentShape(Rectangle())
            .onTapGesture { isComposerFocused = false }
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isResponding) {
                scrollToBottom(proxy)
            }
        }
    }

    private static let typingIndicatorID = "assistant.typing"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? = viewModel.isResponding
            ? Self.typingIndicatorID
            : viewModel.messages.last?.id
        guard let target else { return }

        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func bubble(for message: AssistantMessage) -> some View {
        if message.isAssistant {
            HStack(alignment: .bottom, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
                    .frame(width: 22, height: 22)
                    .background(PrivionyxTheme.Colors.accentSoft, in: Circle())

                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 14)
                    .background(
                        PrivionyxTheme.Colors.accentSoft,
                        in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous)
                    )
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous)
                            .stroke(PrivionyxTheme.Colors.accent.opacity(0.22), lineWidth: 1)
                    )

                Spacer(minLength: 24)
            }
        } else {
            HStack {
                Spacer(minLength: 48)

                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 14)
                    .background(
                        PrivionyxTheme.Colors.glassFillStrong,
                        in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 4, topTrailingRadius: 16, style: .continuous)
                    )
            }
        }
    }

    // MARK: - Input

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.suggestions, id: \.self) { suggestion in
                    Button {
                        isComposerFocused = false
                        viewModel.send(suggestion: suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(PrivionyxTheme.Colors.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .privionyxGlass(cornerRadius: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isResponding)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask about your expenses…", text: $viewModel.input)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(PrivionyxTheme.Colors.fieldText)
                .focused($isComposerFocused)
                .submitLabel(.send)
                .onSubmit { viewModel.send() }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .privionyxGlass(cornerRadius: 22)

            Button {
                viewModel.send()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.onAccent)
                    .frame(width: 44, height: 44)
                    .background(
                        viewModel.canSend ? PrivionyxTheme.Colors.accent : PrivionyxTheme.Colors.accent.opacity(0.35),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.canSend == false)
            .accessibilityLabel("Send message")
        }
    }
}

/// Three bouncing dots shown while the assistant composes a reply.
private struct TypingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(PrivionyxTheme.Colors.accentStrong)
                    .frame(width: 6, height: 6)
                    .offset(y: isAnimating ? -4 : 0)
                    .opacity(isAnimating ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(PrivionyxTheme.Colors.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { isAnimating = true }
        .accessibilityLabel("Assistant is typing")
    }
}

#Preview {
    AssistantView(appState: PrivionyxAppState(container: .preview))
}
