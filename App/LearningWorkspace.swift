import SwiftUI

struct AcademyHeader: View {
  var compact = false

  var body: some View {
    HStack(spacing: 12) {
      Text("TIA")
        .font(.system(compact ? .caption : .headline, design: .rounded, weight: .black))
        .foregroundStyle(.white)
        .frame(width: compact ? 38 : 48, height: compact ? 38 : 48)
        .background(
          LinearGradient(
            colors: [Theme.brandBlue, Theme.brandNavy],
            startPoint: .topLeading,
            endPoint: .bottomTrailing),
          in: RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
      VStack(alignment: .leading, spacing: 2) {
        Text("TERTIARY INFOTECH ACADEMY")
          .font(.caption2.weight(.bold))
          .tracking(1.1)
          .foregroundStyle(Theme.brandBlue)
        Text(compact ? "Official learning access" : "Your official academy learning workspace")
          .font(compact ? .caption : .subheadline.weight(.medium))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Tertiary Infotech Academy official learning access")
  }
}

struct RoleWorkspaceCard: View {
  @EnvironmentObject var store: Store

  private var nextSession: ClassSession? { store.upcoming.first }
  private var nextCourse: Course? {
    guard let courseID = nextSession?.courseID else { return store.dashboard.courses.first }
    return store.dashboard.courses.first(where: { $0.id == courseID })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 5) {
          Text(store.role == "trainer" ? "SESSION COMMAND CENTRE" : "MY LEARNING PASSPORT")
            .font(.caption.weight(.bold))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.82))
          Text(
            store.role == "trainer"
              ? "Prepare the room. Lead the learning." : "Prepare once. Arrive ready."
          )
          .font(.title2.bold())
          .foregroundStyle(.white)
        }
        Spacer()
        Image(
          systemName: store.role == "trainer"
            ? "person.crop.rectangle.stack.fill" : "person.text.rectangle.fill"
        )
        .font(.title2)
        .foregroundStyle(.white)
        .padding(11)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
      }

      if let session = nextSession, let course = nextCourse {
        VStack(alignment: .leading, spacing: 7) {
          Text("NEXT ASSIGNED SESSION")
            .font(.caption2.weight(.bold))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.72))
          Text(course.title).font(.headline).foregroundStyle(.white).lineLimit(2)
          Label(
            "\(session.dateLabel) · \(session.timeLabel)–\(session.endTimeLabel) SGT",
            systemImage: "calendar.badge.clock"
          )
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.9))
          Label(
            session.venue?.isEmpty == false
              ? session.venue! : (session.format ?? "Class details in portal"),
            systemImage: "mappin.and.ellipse"
          )
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.9))
          .lineLimit(1)
        }

        HStack(spacing: 10) {
          WorkspacePill(
            symbol: "checkmark.seal.fill",
            text: "Assigned by TIA")
          WorkspacePill(
            symbol: "folder.fill",
            text: "\(store.publishedCount(for: course)) resources")
          WorkspacePill(
            symbol: store.notifications ? "bell.badge.fill" : "bell.slash.fill",
            text: store.notifications ? "Reminders on" : "Reminders off")
        }

        NavigationLink {
          CourseDetail(course: course)
        } label: {
          HStack {
            Label(
              store.role == "trainer" ? "Open teaching kit" : "Open learning kit",
              systemImage: "arrow.right.circle.fill")
            Spacer()
            Text("\(store.openedCount(for: course))/\(store.publishedCount(for: course)) opened")
              .font(.caption)
              .foregroundStyle(.white.opacity(0.78))
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .padding(14)
          .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workspace-kit")
      } else {
        Text(
          "Your academy-assigned courses and class sessions will appear here after they are published in Tertiary LMS."
        )
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.9))
      }
    }
    .padding(22)
    .background(
      LinearGradient(
        colors: [Theme.brandBlue, Theme.brandNavy],
        startPoint: .topLeading,
        endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 26, style: .continuous)
    )
    .accessibilityElement(children: .contain)
  }
}

struct WorkspacePill: View {
  let symbol: String
  let text: String

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.white)
      .lineLimit(1)
      .minimumScaleFactor(0.72)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 9)
      .padding(.horizontal, 6)
      .background(.white.opacity(0.12), in: Capsule())
  }
}

struct JourneyProgress: View {
  @EnvironmentObject var store: Store
  let course: Course

  private var total: Int { store.publishedCount(for: course) }
  private var opened: Int { store.openedCount(for: course) }
  private var fraction: Double { total == 0 ? 0 : Double(opened) / Double(total) }

  var body: some View {
    HStack(spacing: 10) {
      ZStack {
        Circle().stroke(Theme.accent.opacity(0.16), lineWidth: 5)
        Circle()
          .trim(from: 0, to: fraction)
          .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Text("\(opened)").font(.caption.bold()).foregroundStyle(Theme.accent)
      }
      .frame(width: 38, height: 38)
      VStack(alignment: .leading, spacing: 2) {
        Text(store.role == "trainer" ? "Teaching kit" : "Learning kit")
          .font(.caption.weight(.semibold))
        Text(
          total == 0
            ? "Awaiting publication" : "\(opened) of \(total) resources opened on this device"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
