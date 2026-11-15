import Foundation

/// Live state for one open area: sections, tasks, chores, calendar events,
/// members, recent activity — plus the Realtime subscription that keeps it
/// fresh. Created when an area is opened, torn down when it's closed.
@MainActor
final class AreaWorkspaceStore: ObservableObject {
    @Published private(set) var area: Area
    @Published private(set) var myMembership: AreaMember

    @Published var sections: [WorkspaceSection] = []
    @Published var tasks: [TaskItem] = []
    @Published var chores: [Chore] = []
    @Published var events: [CalendarEvent] = []
    @Published var members: [AreaMember] = []
    @Published var recentActivity: [ActivityLogEntry] = []
    @Published var broadcasts: [BroadcastMessage] = []
    @Published var isLoading = true
    @Published var lastError: String?
    @Published private(set) var pendingUndo: UndoAction?

    struct UndoAction: Identifiable {
        let id = UUID()
        let message: String
        let restore: () async -> Void
    }

    private var undoDismissTask: Task<Void, Never>?

    private let workspaceService = WorkspaceService()
    private let choreService = ChoreService()
    private let calendarService = CalendarService()
    private let areaService: AreaService
    private let activityService = ActivityService()
    private let broadcastService = BroadcastService()
    private let realtime = RealtimeSyncManager()

    var canWrite: Bool { myMembership.role.canWrite }
    var myMemberId: UUID { myMembership.id }

    init(area: Area, myMembership: AreaMember, device: DeviceIdentity) {
        self.area = area
        self.myMembership = myMembership
        self.areaService = AreaService(device: device)
    }

    func start() async {
        await loadAll()
        realtime.start(areaId: area.id) { [weak self] in
            Task { await self?.loadAll() }
        }
    }

    func stop() {
        realtime.stop()
    }

    func loadAll() async {
        isLoading = sections.isEmpty && tasks.isEmpty
        defer { isLoading = false }
        do {
            async let areaResult = areaService.fetchArea(id: area.id)
            async let sectionsResult = workspaceService.fetchSections(areaId: area.id)
            async let tasksResult = workspaceService.fetchTasks(areaId: area.id)
            async let choresResult = choreService.fetchChores(areaId: area.id)
            async let eventsResult = calendarService.fetchEvents(areaId: area.id)
            async let membersResult = areaService.fetchMembers(areaId: area.id)
            async let activityResult = activityService.fetchRecent(areaId: area.id)
            async let broadcastsResult = broadcastService.fetchRecent(areaId: area.id)

            area = try await areaResult
            sections = try await sectionsResult
            tasks = try await tasksResult
            chores = try await choresResult
            events = try await eventsResult
            members = try await membersResult
            recentActivity = try await activityResult
            broadcasts = try await broadcastsResult

            // Pick up role/status changes to my own membership live (e.g. a
            // manager promotes/demotes me while I have the area open).
            if let updatedSelf = members.first(where: { $0.id == myMembership.id }) {
                myMembership = updatedSelf
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func member(_ id: UUID?) -> AreaMember? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }

    func members(_ ids: [UUID]) -> [AreaMember] {
        ids.compactMap { id in members.first { $0.id == id } }
    }

    func tasks(in sectionId: UUID) -> [TaskItem] {
        tasks.filter { $0.sectionId == sectionId }
    }

    func pendingMembers: [AreaMember] {
        members.filter { $0.status == .pending }
    }

    /// Shows a bottom "X deleted · Undo" banner (see `UndoToastView`) for a
    /// few seconds. `restore` should undo exactly the one delete that
    /// triggered this — soft-deletes are cheap to reverse, so every delete
    /// action in the app routes through this instead of just vanishing.
    func showUndo(message: String, restore: @escaping () async -> Void) {
        undoDismissTask?.cancel()
        pendingUndo = UndoAction(message: message, restore: restore)
        undoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.pendingUndo = nil
        }
    }

    func performUndo() async {
        guard let action = pendingUndo else { return }
        undoDismissTask?.cancel()
        pendingUndo = nil
        await action.restore()
        await loadAll()
    }

    func dismissUndo() {
        undoDismissTask?.cancel()
        pendingUndo = nil
    }
}
