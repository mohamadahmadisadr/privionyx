import SwiftUI

/// Compact confirmation of what was pulled off the receipt, shown as soon as parsing
/// finishes. Mirrors the prototype's result sheet; the full editor is one tap away for
/// anything the parser got wrong.
struct ReceiptResultSheet: View {
    let viewModel: AddReceiptViewModel
    let onRetake: () -> Void
    let onEditDetails: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            capturedBadge

            VStack(spacing: 11) {
                summaryRow(title: "Vendor") {
                    Text(viewModel.merchant.isEmpty ? "Not detected" : viewModel.merchant)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(viewModel.merchant.isEmpty ? PrivionyxTheme.Colors.tertiaryInk : PrivionyxTheme.Colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                summaryRow(title: "Category") {
                    CategoryTag(title: viewModel.displayCategoryName)
                }

                summaryRow(title: "Date") {
                    Text(viewModel.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                }

                if viewModel.tax.isEmpty == false {
                    summaryRow(title: "Tax") {
                        Text(formatted(viewModel.tax))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(PrivionyxTheme.Colors.ink)
                    }
                }

                Divider()
                    .overlay(PrivionyxTheme.Colors.separator)
                    .padding(.top, 2)

                summaryRow(title: "Total", isEmphasized: true) {
                    Text(viewModel.amount.isEmpty ? "—" : formatted(viewModel.amount))
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.top, 16)

            if viewModel.reviewHints.isEmpty == false {
                hints
                    .padding(.top, 14)
            }

            Button(action: onEditDetails) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Edit details")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.accent)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)

            HStack(spacing: 10) {
                GlassSecondaryButton(title: "Retake", action: onRetake)
                GlassPrimaryButton(title: viewModel.isEditing ? "Update" : "Save Receipt", action: onSave)
                    .opacity(viewModel.canSave ? 1 : 0.5)
                    .disabled(viewModel.canSave == false)
            }
            .padding(.top, 18)
        }
    }

    private var capturedBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(PrivionyxTheme.Colors.onAccent)
                .frame(width: 24, height: 24)
                .background(PrivionyxTheme.Colors.accent, in: Circle())

            Text("Receipt captured")
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)
        }
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(viewModel.reviewHints, id: \.self) { hint in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(PrivionyxTheme.Colors.warning)
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)

                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .privionyxGlass(cornerRadius: 12)
    }

    private func summaryRow<Value: View>(
        title: String,
        isEmphasized: Bool = false,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: isEmphasized ? 14 : 13, weight: isEmphasized ? .bold : .semibold))
                .foregroundStyle(isEmphasized ? PrivionyxTheme.Colors.ink.opacity(0.7) : PrivionyxTheme.Colors.secondaryInk)

            Spacer(minLength: 12)

            value()
        }
    }

    /// The view model holds raw text field strings; render them as currency for display.
    private func formatted(_ rawValue: String) -> String {
        guard let amount = Double(rawValue.replacingOccurrences(of: ",", with: ".")) else {
            return rawValue
        }
        return PrivionyxCurrencyFormatter.string(for: amount)
    }
}
