import SwiftUI

// Class quizzes opened from the trainer's quiz QR code:
// https://lms-tms.tertiaryinfotech.com/quiz/<courseId>/<quizId>
// (GET /api/courses/quiz, POST /api/courses/submit-quiz).

// MARK: - Link

/// The course and quiz named by a quiz QR code link.
struct QuizLink: Identifiable, Hashable {
  let courseID: String
  let quizID: String
  var id: String { courseID + "/" + quizID }

  /// Accepts only `https://<portal host>/quiz/<courseId>/<quizId>`; nil for any other link.
  static func parse(_ url: URL) -> QuizLink? {
    guard url.scheme?.lowercased() == "https",
      let host = url.host?.lowercased(), host == API.shared.base.host?.lowercased(),
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(
      String.init)
    guard parts.count == 3, parts[0] == "quiz" else { return nil }
    let course = parts[1].trimmingCharacters(in: .whitespaces)
    let quiz = parts[2].trimmingCharacters(in: .whitespaces)
    guard !course.isEmpty, !quiz.isEmpty else { return nil }
    return QuizLink(courseID: course, quizID: quiz)
  }

  /// The same check for text read from a QR code.
  static func parse(_ text: String) -> QuizLink? {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      return nil
    }
    return parse(url)
  }
}

// MARK: - Models

/// An id the server may send as a string or a number.
private func flexibleID<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) throws
  -> String
{
  if let text = try? container.decode(String.self, forKey: key) { return text }
  if let number = try? container.decode(Int.self, forKey: key) { return String(number) }
  throw DecodingError.dataCorruptedError(
    forKey: key, in: container, debugDescription: "Expected a string or number id")
}

struct QuizQuestion: Decodable, Identifiable, Equatable {
  let id: String
  let question: String
  let options: [String]
  let correctIndex: Int?

  init(id: String, question: String, options: [String], correctIndex: Int?) {
    self.id = id
    self.question = question
    self.options = options
    self.correctIndex = correctIndex
  }
  enum CodingKeys: String, CodingKey { case id, question, options, correctIndex }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try flexibleID(c, .id)
    question = (try? c.decode(String.self, forKey: .question)) ?? ""
    options = (try? c.decode([String].self, forKey: .options)) ?? []
    correctIndex = try? c.decode(Int.self, forKey: .correctIndex)
  }
}

struct Quiz: Decodable, Equatable {
  let id: String
  let courseId: String
  let title: String
  var courseTitle: String?
  var courseCode: String?
  let questions: [QuizQuestion]

  /// Scores answers the way the server does: one mark for each question whose chosen
  /// option is the correct one. Used for the sample quiz and as a fallback for the review.
  func score(answers: [String: Int], attemptID: String = "", completedAt: String? = nil)
    -> QuizResult
  {
    let breakdown = questions.map { q -> QuizResult.Item in
      let selected = answers[q.id]
      return QuizResult.Item(
        questionId: q.id, correct: selected != nil && selected == q.correctIndex,
        correctIndex: q.correctIndex, selectedIndex: selected)
    }
    return QuizResult(
      attemptId: attemptID, completedAt: completedAt, score: breakdown.filter(\.correct).count,
      total: questions.count, breakdown: breakdown)
  }
}

struct QuizAttempt: Decodable, Equatable {
  let score: Int
  let total: Int
  var completedAt: String?

  var percent: Int { QuizResult.percent(score: score, total: total) }
  /// "20 Nov 2026, 14:05" in Singapore time, or nil when the server sent no usable date.
  var completedLabel: String? {
    guard let completedAt else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = iso.date(from: completedAt)
    if date == nil {
      iso.formatOptions = [.withInternetDateTime]
      date = iso.date(from: completedAt)
    }
    guard let date else { return nil }
    let out = DateFormatter()
    out.locale = Locale(identifier: "en_SG")
    out.timeZone = TimeZone(identifier: "Asia/Singapore")
    out.dateFormat = "d MMM yyyy, HH:mm"
    return out.string(from: date)
  }
}

struct QuizReply: Decodable {
  let quiz: Quiz
  var previous: QuizAttempt?
}

struct QuizResult: Decodable, Equatable {
  struct Item: Decodable, Equatable {
    let questionId: String
    let correct: Bool
    let correctIndex: Int?
    let selectedIndex: Int?

    init(questionId: String, correct: Bool, correctIndex: Int?, selectedIndex: Int?) {
      self.questionId = questionId
      self.correct = correct
      self.correctIndex = correctIndex
      self.selectedIndex = selectedIndex
    }
    enum CodingKeys: String, CodingKey { case questionId, correct, correctIndex, selectedIndex }
    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      questionId = try flexibleID(c, .questionId)
      correct = (try? c.decode(Bool.self, forKey: .correct)) ?? false
      correctIndex = try? c.decode(Int.self, forKey: .correctIndex)
      selectedIndex = try? c.decode(Int.self, forKey: .selectedIndex)
    }
  }
  /// One question of the result screen: what was chosen and which option was right.
  struct Review: Identifiable, Equatable {
    let id: String
    let number: Int
    let question: String
    let options: [String]
    let selectedIndex: Int?
    let correctIndex: Int?
    let correct: Bool
  }

  let attemptId: String
  var completedAt: String?
  let score: Int
  let total: Int
  let breakdown: [Item]

  init(attemptId: String, completedAt: String?, score: Int, total: Int, breakdown: [Item]) {
    self.attemptId = attemptId
    self.completedAt = completedAt
    self.score = score
    self.total = total
    self.breakdown = breakdown
  }
  enum CodingKeys: String, CodingKey { case attemptId, completedAt, score, total, breakdown }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    attemptId = (try? flexibleID(c, .attemptId)) ?? ""
    completedAt = try? c.decode(String.self, forKey: .completedAt)
    score = try c.decode(Int.self, forKey: .score)
    total = try c.decode(Int.self, forKey: .total)
    breakdown = (try? c.decode([Item].self, forKey: .breakdown)) ?? []
  }

  var percent: Int { Self.percent(score: score, total: total) }
  static func percent(score: Int, total: Int) -> Int {
    total > 0 ? Int((Double(score) / Double(total) * 100).rounded()) : 0
  }

  /// Pairs the server's marking with the quiz questions, in question order. A question the
  /// server did not mark falls back to the learner's own answer and the quiz's answer key.
  func review(for quiz: Quiz, answers: [String: Int]) -> [Review] {
    let marked = Dictionary(breakdown.map { ($0.questionId, $0) }, uniquingKeysWith: { a, _ in a })
    return quiz.questions.enumerated().map { index, q in
      let item = marked[q.id]
      let selected = item?.selectedIndex ?? answers[q.id]
      let right = item?.correctIndex ?? q.correctIndex
      return Review(
        id: q.id, number: index + 1, question: q.question, options: q.options,
        selectedIndex: selected, correctIndex: right,
        correct: item?.correct ?? (selected != nil && selected == right))
    }
  }
}

// MARK: - Quiz data (live or sample)

extension Store {
  /// Opens the quiz for a scanned or tapped link. When nobody is signed in it waits:
  /// the sign-in screen shows first and the quiz opens straight after.
  func open(quiz link: QuizLink) {
    if pendingQuiz != link { pendingQuiz = link }
  }

  /// Handles an incoming link. Returns false when it is not a quiz link.
  @discardableResult func handle(url: URL) -> Bool {
    guard let link = QuizLink.parse(url) else { return false }
    open(quiz: link)
    return true
  }

  func quiz(_ link: QuizLink) async throws -> QuizReply {
    if demo { return QuizReply(quiz: Sample.quiz(link: link), previous: demoQuizAttempts[link.id]) }
    return try await API.shared.request(
      "courses/quiz", query: ["courseId": link.courseID, "quizId": link.quizID])
  }

  func submit(quiz: Quiz, link: QuizLink, answers: [String: Int]) async throws -> QuizResult {
    if demo {
      let result = quiz.score(answers: answers, attemptID: "sample")
      demoQuizAttempts[link.id] = QuizAttempt(
        score: result.score, total: result.total,
        completedAt: ISO8601DateFormatter().string(from: Date()))
      return result
    }
    guard let userID = user?.id else {
      throw APIError(message: "Please sign in to submit this quiz.")
    }
    return try await API.shared.request(
      "courses/submit-quiz", method: "POST",
      body: [
        "userId": userID, "courseId": link.courseID, "quizId": link.quizID, "answers": answers,
      ])
  }
}

// MARK: - Quiz screen

struct QuizView: View {
  @EnvironmentObject var store: Store
  let link: QuizLink
  let onClose: () -> Void

  enum Phase: Equatable { case loading, failed(String), previous, answering, result }
  @State private var phase = Phase.loading
  @State private var quiz: Quiz?
  @State private var previous: QuizAttempt?
  @State private var index = 0
  @State private var answers: [String: Int] = [:]
  @State private var result: QuizResult?
  @State private var submitting = false
  @State private var problem: String?
  @State private var confirmLeave = false

  var body: some View {
    NavigationStack {
      Group {
        switch phase {
        case .loading:
          ProgressView("Loading quiz…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
          ContentUnavailableView {
            Label("Quiz not available", systemImage: "questionmark.circle")
          } description: {
            Text(message)
          } actions: {
            Button("Try again") { Task { await load() } }.buttonStyle(.bordered)
          }
        case .previous: previousView
        case .answering: questionView
        case .result: resultView
        }
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle(quiz?.title ?? "Quiz").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            if phase == .answering && !answers.isEmpty { confirmLeave = true } else { onClose() }
          }.accessibilityIdentifier("quiz-close")
        }
      }
      .confirmationDialog(
        "Leave this quiz?", isPresented: $confirmLeave, titleVisibility: .visible
      ) {
        Button("Leave quiz", role: .destructive) { onClose() }
        Button("Keep answering", role: .cancel) {}
      } message: {
        Text("Your answers have not been submitted and will not be saved.")
      }
      .alert(
        "Quiz", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
      ) {
        Button("OK") { problem = nil }
      } message: {
        Text(problem ?? "")
      }
    }
    .interactiveDismissDisabled(phase == .answering && !answers.isEmpty)
    .task(id: link) { await load() }
  }

  // MARK: Header

  @ViewBuilder private var courseHeader: some View {
    if let quiz {
      VStack(alignment: .leading, spacing: 6) {
        if store.demo {
          Text("SAMPLE QUIZ").font(.caption2.weight(.bold)).tracking(1.2)
            .foregroundStyle(.secondary)
        }
        if let code = quiz.courseCode, !code.isEmpty {
          Label(code, systemImage: "book.closed.fill").font(.caption).foregroundStyle(Theme.accent)
        }
        if let course = quiz.courseTitle, !course.isEmpty {
          Text(course).font(.subheadline).foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func scoreCard(title: String, score: Int, total: Int, footnote: String?) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.caption.bold()).tracking(2)
      Text("\(score) / \(total)").font(.system(size: 52, weight: .bold, design: .rounded))
        .accessibilityIdentifier("quiz-score")
      Text("\(QuizResult.percent(score: score, total: total))% correct").font(.headline)
      if let footnote { Text(footnote).font(.footnote).opacity(0.85) }
    }
    .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(26)
    .background(
      LinearGradient(
        colors: [Theme.hero, Theme.brandNavy], startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 28)
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title.capitalized): \(score) out of \(total)")
  }

  // MARK: Last attempt

  private var previousView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        courseHeader
        if let previous {
          scoreCard(
            title: "YOUR LAST SCORE", score: previous.score, total: previous.total,
            footnote: previous.completedLabel.map { "Completed \($0) SGT" })
        }
        Text(
          "You have already taken this quiz. You can retake it; your latest attempt is the one your trainer sees."
        ).font(.subheadline).foregroundStyle(.secondary)
        Button {
          start()
        } label: {
          Label("Retake quiz", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
            .padding(6)
        }.buttonStyle(.borderedProminent).accessibilityIdentifier("quiz-retake")
        Button {
          onClose()
        } label: {
          Text("Done").frame(maxWidth: .infinity).padding(6)
        }.buttonStyle(.bordered).accessibilityIdentifier("quiz-done")
      }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
    }
  }

  // MARK: Question

  @ViewBuilder private var questionView: some View {
    if let quiz, quiz.questions.indices.contains(index) {
      let question = quiz.questions[index]
      let last = index == quiz.questions.count - 1
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          courseHeader
          VStack(alignment: .leading, spacing: 8) {
            Text("Question \(index + 1) of \(quiz.questions.count)").font(.caption.bold())
              .tracking(1).foregroundStyle(.secondary).accessibilityIdentifier("quiz-progress")
            ProgressView(value: Double(index + 1), total: Double(quiz.questions.count))
              .tint(Theme.accent)
          }
          Text(question.question).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
          VStack(spacing: 12) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { offset, option in
              let chosen = answers[question.id] == offset
              Button {
                answers[question.id] = offset
              } label: {
                HStack(alignment: .top, spacing: 14) {
                  Image(systemName: chosen ? "largecircle.fill.circle" : "circle").font(.title3)
                    .foregroundStyle(chosen ? Theme.accent : Color.secondary)
                  Text(option).font(.body).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                  Spacer(minLength: 0)
                }
                .padding(16).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(
                  Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 16).stroke(
                    chosen ? Theme.accent : Color.clear, lineWidth: 2))
              }
              .buttonStyle(.plain).accessibilityIdentifier("quiz-option-\(offset)")
              .accessibilityAddTraits(chosen ? .isSelected : [])
            }
          }
        }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
      }
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 12) {
          if index > 0 {
            Button {
              index -= 1
            } label: {
              Text("Back").frame(maxWidth: .infinity).padding(6)
            }.buttonStyle(.bordered).disabled(submitting).accessibilityIdentifier("quiz-back")
          }
          Button {
            if last { Task { await submit() } } else { index += 1 }
          } label: {
            Text(last ? (submitting ? "Submitting…" : "Submit") : "Next")
              .frame(maxWidth: .infinity).padding(6)
          }
          .buttonStyle(.borderedProminent)
          .disabled(answers[question.id] == nil || submitting)
          .accessibilityIdentifier(last ? "quiz-submit" : "quiz-next")
        }
        .padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: 620)
        .frame(maxWidth: .infinity).background(.bar)
      }
    } else {
      ContentUnavailableView(
        "No questions yet", systemImage: "questionmark.circle",
        description: Text("Your trainer has not added questions to this quiz."))
    }
  }

  // MARK: Result

  @ViewBuilder private var resultView: some View {
    if let quiz, let result {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          courseHeader
          scoreCard(
            title: "YOUR SCORE", score: result.score, total: result.total,
            footnote: store.demo ? "Sample quiz. Nothing was sent to the academy." : nil)
          Text("Review").font(.title2.bold())
          ForEach(result.review(for: quiz, answers: answers)) { item in reviewCard(item) }
          Button {
            start()
          } label: {
            Label("Retake quiz", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
              .padding(6)
          }.buttonStyle(.bordered).accessibilityIdentifier("quiz-retake")
          Button {
            onClose()
          } label: {
            Text("Done").frame(maxWidth: .infinity).padding(6)
          }.buttonStyle(.borderedProminent).accessibilityIdentifier("quiz-done")
        }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
      }
    }
  }

  private func reviewCard(_ item: QuizResult.Review) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(
        item.correct ? "Question \(item.number) · Correct" : "Question \(item.number) · Incorrect",
        systemImage: item.correct ? "checkmark.circle.fill" : "xmark.circle.fill"
      )
      .font(.caption.bold()).foregroundStyle(item.correct ? Color.green : Color.red)
      Text(item.question).font(.headline).fixedSize(horizontal: false, vertical: true)
      ForEach(Array(item.options.enumerated()), id: \.offset) { offset, option in
        let right = offset == item.correctIndex
        let chosen = offset == item.selectedIndex
        HStack(alignment: .top, spacing: 10) {
          Image(
            systemName: right ? "checkmark.circle.fill" : chosen ? "xmark.circle.fill" : "circle"
          ).foregroundStyle(right ? Color.green : chosen ? Color.red : Color.secondary)
          VStack(alignment: .leading, spacing: 2) {
            Text(option).font(.subheadline).fontWeight(right || chosen ? .semibold : .regular)
            if right || chosen {
              Text(
                right && chosen ? "Your answer · Correct" : right ? "Correct answer" : "Your answer"
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
      }
      if item.selectedIndex == nil {
        Text("Not answered").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    .accessibilityIdentifier("quiz-review-\(item.number)")
  }

  // MARK: Actions

  private func start() {
    answers = [:]
    index = 0
    result = nil
    phase = .answering
  }

  private func load() async {
    phase = .loading
    do {
      let reply = try await store.quiz(link)
      quiz = reply.quiz
      previous = reply.previous
      if reply.previous != nil { phase = .previous } else { start() }
    } catch {
      phase = .failed(
        error.localizedDescription == "Quiz not found"
          ? "This quiz is no longer available. Ask your trainer to show the QR code again."
          : error.localizedDescription)
    }
  }

  private func submit() async {
    guard let quiz, !submitting else { return }
    submitting = true
    defer { submitting = false }
    do {
      let marked = try await store.submit(quiz: quiz, link: link, answers: answers)
      result = marked
      previous = QuizAttempt(
        score: marked.score, total: marked.total, completedAt: marked.completedAt)
      phase = .result
    } catch { problem = error.localizedDescription }
  }
}

extension View {
  /// A taller, page-sized sheet on iPad, so a question or the review is not cramped.
  @ViewBuilder func pageSizedSheet() -> some View {
    if #available(iOS 18.0, *) { presentationSizing(.page) } else { self }
  }
}
