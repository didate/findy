import SwiftUI

/// Asks what to do when incoming items have names that are already taken.
///
/// A sheet rather than a system alert: an alert shows three buttons at most, and this choice needs
/// four, with a visible way to back out.
struct ConflictSheet: View {
    let transfer: PendingTransfer
    let onChoice: (ConflictChoice?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Some items already exist in this location.", bundle: .module)
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(transfer.conflictNames, id: \.self) { name in
                        Label {
                            Text(verbatim: name).lineLimit(1).truncationMode(.middle)
                        } icon: {
                            Image(systemName: "doc")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
            Text("Replaced items are moved to the Trash.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    onChoice(nil)
                } label: {
                    Text("Cancel", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    onChoice(.skip)
                } label: {
                    Text("Skip", bundle: .module)
                }
                Button {
                    onChoice(.replace)
                } label: {
                    Text("Replace", bundle: .module)
                }
                Button {
                    onChoice(.keepBoth)
                } label: {
                    Text("Keep Both", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
