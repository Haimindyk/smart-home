import Foundation

/// Live state for one open area: sections, tasks, chores, calendar events,
/// members, recent activity — plus the Realtime subscription that keeps it
/// fresh. Created when an area is opened, torn down when it's closed.
@MainActor
final class AreaWorkspaceStore: ObservableObject {
    let area: Area
    let myMembership: AreaMember

    @Published var sections: [WorkspaceSection] = []
    @Published var tasks: [TaskItem] = []
    @Published var chores: [Chore] = []
    @Published var events: [CalendarEvent] = []
    @Published var members: [AreaMember] = []
    @Published var recentActivity: [ActivityLogEntry] = []
    @Published var isLoading = true
    @Published var lastError: String?

    private let workspaceService = WorkspaceService()
    private let choreService = ChoreService()
    private let calendarService = CalendarService()
    private let areaService: AreaService
    private let activityService = ActivityService()
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
            async let sectionsResult = workspaceService.fetchSections(areaId: area.id)
            async let tasksResult = workspaceService.fetchTasks(areaId: area.id)
            async let choresResult = choreService.fetchChores(areaId: area.id)
            async let eventsResult = calendarService.fetchEvents(areaId: area.id)
            async let membersResult = areaService.fetchMembers(areaId: area.id)
            async let activityResult = activityService.fetchRecent(areaId: area.id)

            sections = try await sectionsResult
            tasks = try await tasksResult
            chores = try await choresResult
            events = try await eventsResult
            members = try await membersResult
            recentActivity = try await activityResult
        } catch {
            lastError = error.localizedDescription
        }
    }

    func member(_ id: UUID?) -> AreaMember? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }

    func tasks(in sectionId: UUID) -> [TaskItem] {
        tasks.filter { $0.sectionId == sectionId }
    }

    func pendingMembers: [AreaMember] {
        members.filter { $0.status == .pending }
    }
}
