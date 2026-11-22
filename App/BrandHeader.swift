import SwiftUI

/// The Tertiary Infotech Academy header used on the sign-in screen of every TIA app:
/// the academy logo, "Tertiary Infotech Academy", then the app's own name
/// (TIA TMS, TIA LMS SG / MY / GH). This file is identical in every TIA app.
struct AcademyBrandHeader: View {
    let appName: String
    var body: some View {
        VStack(spacing: 10) {
            Image("AcademyLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .shadow(color: Color(red: 0.04, green: 0.24, blue: 0.56).opacity(0.25), radius: 12, y: 6)
                .accessibilityHidden(true)
            Text("Tertiary Infotech Academy")
                .font(.system(size: 26, weight: .heavy))
                .multilineTextAlignment(.center)
            Text(appName)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tertiary Infotech Academy, \(appName)")
    }
}

/// The admin sign-in page, opened from the quiet "Admin sign-in" link in the sign-in
/// footer: the academy header and one big "Continue with Google" button, as in the HRMS
/// app. Only allow-listed admin accounts get in; the server holds the list.
struct AdminSignInPage: View {
    let appName: String
    let busy: Bool
    let error: String?
    let signIn: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    AcademyBrandHeader(appName: appName)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Admin sign-in").font(.title2.bold())
                            Text("For academy administrators. Continue with your company Google account.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        GoogleSignInButton(loading: busy, enabled: !busy, action: signIn)
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Label("Only approved admin accounts can sign in here.", systemImage: "lock.shield")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.secondary.opacity(0.2)))
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(busy)
                }
            }
        }
    }
}

/// "Continue with Google": Google's white button treatment (their branding guidelines
/// require the unmodified four-colour mark on white), the same as the HRMS app.
struct GoogleSignInButton: View {
    var loading = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if loading {
                    ProgressView().tint(Color(red: 0.26, green: 0.26, blue: 0.26))
                } else {
                    GoogleGlyph().frame(width: 20, height: 20)
                    Text("Continue with Google")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(enabled && !loading ? 1 : 0.55)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 0.85, green: 0.86, blue: 0.89), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || loading)
        .accessibilityLabel("Continue with Google")
        .accessibilityIdentifier("googleSignIn")
    }
}

/// The Google "G", drawn from Google's own SVG path data.
private struct GoogleGlyph: View {
    /// Each stroke of the mark: Google's published path data, one colour each.
    private static let paths: [(String, Color)] = [
        // Blue
        ("M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17z",
         Color(red: 0.259, green: 0.522, blue: 0.957)),
        // Green
        ("M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46z",
         Color(red: 0.204, green: 0.659, blue: 0.325)),
        // Yellow
        ("M11.69 28.18C11.25 26.86 11 25.45 11 24s.25-2.86.69-4.18v-5.7H4.34C2.85 17.09 2 20.45 2 24s.85 6.91 2.34 9.88l7.35-5.7z",
         Color(red: 0.984, green: 0.737, blue: 0.020)),
        // Red
        ("M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z",
         Color(red: 0.918, green: 0.263, blue: 0.208)),
    ]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let scale = side / 48   // Google ships the mark on a 48×48 canvas.
            ZStack {
                ForEach(Array(Self.paths.enumerated()), id: \.offset) { _, entry in
                    GoogleMarkShape(command: entry.0)
                        .fill(entry.1)
                        .frame(width: 48, height: 48)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: side, height: side, alignment: .topLeading)
                }
            }
            .frame(width: side, height: side)
        }
    }
}

private struct GoogleMarkShape: Shape {
    let command: String

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var numbers: [CGFloat] = []
        var op: Character = "M"

        func flush() {
            guard !numbers.isEmpty || op == "Z" || op == "z" else { return }
            var i = 0
            switch op {
            case "M", "m":
                while i + 1 < numbers.count {
                    let p = point(numbers[i], numbers[i + 1], relative: op == "m", from: current)
                    if i == 0 { path.move(to: p); start = p } else { path.addLine(to: p) }
                    current = p
                    i += 2
                }
            case "L", "l":
                while i + 1 < numbers.count {
                    let p = point(numbers[i], numbers[i + 1], relative: op == "l", from: current)
                    path.addLine(to: p); current = p
                    i += 2
                }
            case "H", "h":
                while i < numbers.count {
                    let x = op == "h" ? current.x + numbers[i] : numbers[i]
                    let p = CGPoint(x: x, y: current.y)
                    path.addLine(to: p); current = p
                    i += 1
                }
            case "V", "v":
                while i < numbers.count {
                    let y = op == "v" ? current.y + numbers[i] : numbers[i]
                    let p = CGPoint(x: current.x, y: y)
                    path.addLine(to: p); current = p
                    i += 1
                }
            case "C", "c":
                while i + 5 < numbers.count {
                    let rel = op == "c"
                    let c1 = point(numbers[i], numbers[i + 1], relative: rel, from: current)
                    let c2 = point(numbers[i + 2], numbers[i + 3], relative: rel, from: current)
                    let end = point(numbers[i + 4], numbers[i + 5], relative: rel, from: current)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end
                    i += 6
                }
            case "Z", "z":
                path.closeSubpath(); current = start
            default:
                break
            }
            numbers.removeAll()
        }

        var buffer = ""
        func takeNumber() {
            let trimmed = buffer.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, let value = Double(trimmed) { numbers.append(CGFloat(value)) }
            buffer = ""
        }

        for ch in command {
            if ch.isLetter {
                takeNumber(); flush()
                op = ch
            } else if ch == "," || ch == " " {
                takeNumber()
            } else if ch == "-" && !buffer.isEmpty && buffer.last != "e" {
                takeNumber(); buffer = "-"
            } else {
                buffer.append(ch)
            }
        }
        takeNumber(); flush()
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, relative: Bool, from: CGPoint) -> CGPoint {
        relative ? CGPoint(x: from.x + x, y: from.y + y) : CGPoint(x: x, y: y)
    }
}
