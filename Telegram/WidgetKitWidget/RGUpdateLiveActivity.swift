// MARK: Regram — update progress on the Lock Screen and Dynamic Island, using the existing extension.
import ActivityKit
import SwiftUI
import WidgetKit
import RGUpdateActivity

@available(iOSApplicationExtension 16.1, iOS 16.1, *)
struct RGUpdateLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RGUpdateActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    RGUpdateActivityIcon(size: 24)
                    Text(context.attributes.title).font(.headline)
                    Spacer()
                    Text(verbatim: "\(context.attributes.version) · b\(context.attributes.build)").font(.caption).foregroundColor(.secondary)
                }
                RGUpdateActivityProgress(state: context.state, stale: rgUpdateActivityIsStale(context))
                Link(context.state.action, destination: context.attributes.updateURL).font(.caption)
            }.padding(16).activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .widgetURL(context.attributes.updateURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            RGUpdateActivityIcon(size: 22)
                            Text("Regram").font(.headline).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(verbatim: "\(context.attributes.version) · b\(context.attributes.build)")
                                .font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        }
                        RGUpdateActivityProgress(state: context.state, stale: rgUpdateActivityIsStale(context))
                        Link(context.state.action, destination: context.attributes.updateURL).font(.caption).lineLimit(1)
                    }
                    .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 12)
                    .foregroundColor(.white).environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                RGUpdateActivityIcon(size: 20)
            } compactTrailing: {
                RGUpdateActivityIndicator(state: context.state, stale: rgUpdateActivityIsStale(context))
            } minimal: {
                RGUpdateActivityIcon(size: 20).accessibilityLabel(Text(context.state.label))
            }.widgetURL(context.attributes.updateURL).keylineTint(.cyan)
        }
    }
}

@available(iOSApplicationExtension 16.1, iOS 16.1, *)
private struct RGUpdateActivityIcon: View {
    let size: CGFloat
    var body: some View {
        Image("RegramUpdateIcon").renderingMode(.original).resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
    }
}

@available(iOSApplicationExtension 16.1, iOS 16.1, *)
private struct RGUpdateActivityProgress: View {
    let state: RGUpdateActivityAttributes.ContentState
    let stale: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if !state.isDeterminate {
                    if state.phase == "ready" || state.phase == "downloaded" {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    } else {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .cyan)).frame(width: 16, height: 16)
                    }
                }
                Text(stale ? state.staleLabel : state.label).font(.subheadline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if state.isDeterminate { Text("\(Int(state.fraction * 100))%").font(.subheadline).monospacedDigit().fixedSize() }
            }
            if state.isDeterminate {
                ProgressView(value: state.fraction)
                Text("\(ByteCountFormatter.string(fromByteCount: state.downloaded, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: state.total, countStyle: .file))").font(.caption2).foregroundColor(.secondary).monospacedDigit()
            }
        }
    }
}

@available(iOSApplicationExtension 16.1, iOS 16.1, *)
private struct RGUpdateActivityIndicator: View {
    let state: RGUpdateActivityAttributes.ContentState
    let stale: Bool
    var body: some View {
        if stale { Image(systemName: "pause.circle") }
        else if state.isDeterminate { ZStack {
            Circle().stroke(Color.cyan.opacity(0.25), lineWidth: 2)
            Circle().trim(from: 0, to: state.fraction).stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
        }.frame(width: 18, height: 18).accessibilityLabel(Text("\(Int(state.fraction * 100))%")) }
        else if state.phase == "ready" || state.phase == "downloaded" { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
        else { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .cyan)).frame(width: 18, height: 18) }
    }
}

@available(iOSApplicationExtension 16.1, iOS 16.1, *)
private func rgUpdateActivityIsStale(_ context: ActivityViewContext<RGUpdateActivityAttributes>) -> Bool {
    if #available(iOSApplicationExtension 16.2, iOS 16.2, *) { return context.isStale }
    return false
}
