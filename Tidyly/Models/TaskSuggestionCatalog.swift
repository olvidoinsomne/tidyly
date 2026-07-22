import Foundation

struct TaskSuggestion: Identifiable, Hashable {
    let title: String
    let frequencyDays: Int
    let priority: Priority
    let estimatedMinutes: Int

    var id: String { title }
}

struct StarterRoomPlan: Identifiable, Hashable {
    let name: String
    let icon: String
    let color: String
    let tasks: [TaskSuggestion]
    var id: String { name }
}

enum TaskSuggestionCatalog {
    static let starterRooms: [StarterRoomPlan] = [
        StarterRoomPlan(name: "Kitchen", icon: "🍳", color: "#F59E0B", tasks: Array(kitchen.prefix(3))),
        StarterRoomPlan(name: "Primary Bedroom", icon: "🛏️", color: "#8B5CF6", tasks: Array(bedroom.prefix(3))),
        StarterRoomPlan(name: "Bathroom", icon: "🛁", color: "#06B6D4", tasks: Array(bathroom.prefix(3))),
        StarterRoomPlan(name: "Living Room", icon: "🛋️", color: "#3B82F6", tasks: Array(livingRoom.prefix(3))),
        StarterRoomPlan(name: "Dining Room", icon: "🍽️", color: "#EF4444", tasks: Array(diningRoom.prefix(3))),
        StarterRoomPlan(name: "Laundry Room", icon: "🧺", color: "#10B981", tasks: Array(laundry.prefix(3))),
        StarterRoomPlan(name: "Home Office", icon: "💻", color: "#6366F1", tasks: Array(office.prefix(3))),
        StarterRoomPlan(name: "Garage", icon: "🚗", color: "#64748B", tasks: Array(garage.prefix(3)))
    ]

    static let householdSuggestions = [
        TaskSuggestion(title: "Take out trash", frequencyDays: 7, priority: .high, estimatedMinutes: 10),
        TaskSuggestion(title: "Vacuum hallways", frequencyDays: 7, priority: .medium, estimatedMinutes: 20),
        TaskSuggestion(title: "Change HVAC filter", frequencyDays: 90, priority: .medium, estimatedMinutes: 15),
        TaskSuggestion(title: "Test smoke detectors", frequencyDays: 30, priority: .high, estimatedMinutes: 10),
        TaskSuggestion(title: "Clean entryway", frequencyDays: 7, priority: .medium, estimatedMinutes: 15),
        TaskSuggestion(title: "Water household plants", frequencyDays: 7, priority: .medium, estimatedMinutes: 15)
    ]

    static func suggestions(for roomName: String) -> [TaskSuggestion] {
        let name = roomName.lowercased()

        if name.contains("kitchen") { return kitchen }
        if name.contains("bath") || name.contains("restroom") { return bathroom }
        if name.contains("bed") || name.contains("nursery") { return bedroom }
        if name.contains("living") || name.contains("family") || name.contains("lounge") { return livingRoom }
        if name.contains("office") || name.contains("study") { return office }
        if name.contains("laundry") || name.contains("utility") { return laundry }
        if name.contains("garage") || name.contains("workshop") { return garage }
        if name.contains("dining") { return diningRoom }
        return general
    }

    private static let kitchen = [
        TaskSuggestion(title: "Wipe countertops", frequencyDays: 1, priority: .high, estimatedMinutes: 5),
        TaskSuggestion(title: "Clean the sink", frequencyDays: 2, priority: .medium, estimatedMinutes: 10),
        TaskSuggestion(title: "Sweep and mop the floor", frequencyDays: 7, priority: .medium, estimatedMinutes: 20),
        TaskSuggestion(title: "Clean appliance surfaces", frequencyDays: 7, priority: .low, estimatedMinutes: 15),
        TaskSuggestion(title: "Clean inside the refrigerator", frequencyDays: 30, priority: .low, estimatedMinutes: 30)
    ]

    private static let bathroom = [
        TaskSuggestion(title: "Clean the toilet", frequencyDays: 7, priority: .high, estimatedMinutes: 10),
        TaskSuggestion(title: "Clean the sink and counter", frequencyDays: 7, priority: .medium, estimatedMinutes: 10),
        TaskSuggestion(title: "Clean the shower or tub", frequencyDays: 7, priority: .medium, estimatedMinutes: 20),
        TaskSuggestion(title: "Clean mirrors", frequencyDays: 7, priority: .low, estimatedMinutes: 5),
        TaskSuggestion(title: "Mop the floor", frequencyDays: 7, priority: .medium, estimatedMinutes: 10)
    ]

    private static let bedroom = [
        TaskSuggestion(title: "Make the bed", frequencyDays: 1, priority: .medium, estimatedMinutes: 5),
        TaskSuggestion(title: "Dust surfaces", frequencyDays: 7, priority: .low, estimatedMinutes: 10),
        TaskSuggestion(title: "Vacuum the floor", frequencyDays: 7, priority: .medium, estimatedMinutes: 15),
        TaskSuggestion(title: "Change bed linens", frequencyDays: 14, priority: .medium, estimatedMinutes: 15),
        TaskSuggestion(title: "Declutter surfaces", frequencyDays: 7, priority: .low, estimatedMinutes: 10)
    ]

    private static let livingRoom = [
        TaskSuggestion(title: "Tidy and put items away", frequencyDays: 2, priority: .medium, estimatedMinutes: 10),
        TaskSuggestion(title: "Dust furniture and shelves", frequencyDays: 7, priority: .low, estimatedMinutes: 15),
        TaskSuggestion(title: "Vacuum the floor", frequencyDays: 7, priority: .medium, estimatedMinutes: 20),
        TaskSuggestion(title: "Clean screens and electronics", frequencyDays: 14, priority: .low, estimatedMinutes: 10),
        TaskSuggestion(title: "Vacuum upholstery", frequencyDays: 30, priority: .low, estimatedMinutes: 20)
    ]

    private static let office = [
        TaskSuggestion(title: "Clear and wipe the desk", frequencyDays: 7, priority: .medium, estimatedMinutes: 10),
        TaskSuggestion(title: "Dust electronics", frequencyDays: 14, priority: .low, estimatedMinutes: 10),
        TaskSuggestion(title: "Vacuum the floor", frequencyDays: 7, priority: .medium, estimatedMinutes: 15),
        TaskSuggestion(title: "Organize papers", frequencyDays: 14, priority: .low, estimatedMinutes: 15),
        TaskSuggestion(title: "Empty the wastebasket", frequencyDays: 7, priority: .medium, estimatedMinutes: 5)
    ]

    private static let laundry = [
        TaskSuggestion(title: "Wipe washer and dryer", frequencyDays: 7, priority: .low, estimatedMinutes: 10),
        TaskSuggestion(title: "Sweep and mop the floor", frequencyDays: 7, priority: .medium, estimatedMinutes: 15),
        TaskSuggestion(title: "Clean the lint trap area", frequencyDays: 7, priority: .high, estimatedMinutes: 5),
        TaskSuggestion(title: "Organize laundry supplies", frequencyDays: 30, priority: .low, estimatedMinutes: 15),
        TaskSuggestion(title: "Clean the washing machine", frequencyDays: 30, priority: .medium, estimatedMinutes: 20)
    ]

    private static let garage = [
        TaskSuggestion(title: "Sweep the floor", frequencyDays: 14, priority: .medium, estimatedMinutes: 20),
        TaskSuggestion(title: "Put tools and supplies away", frequencyDays: 7, priority: .medium, estimatedMinutes: 15),
        TaskSuggestion(title: "Remove trash and recycling", frequencyDays: 7, priority: .high, estimatedMinutes: 10),
        TaskSuggestion(title: "Wipe work surfaces", frequencyDays: 14, priority: .low, estimatedMinutes: 10),
        TaskSuggestion(title: "Declutter storage areas", frequencyDays: 30, priority: .low, estimatedMinutes: 30)
    ]

    private static let diningRoom = [
        TaskSuggestion(title: "Wipe the dining table", frequencyDays: 2, priority: .medium, estimatedMinutes: 5),
        TaskSuggestion(title: "Dust furniture", frequencyDays: 7, priority: .low, estimatedMinutes: 10),
        TaskSuggestion(title: "Vacuum or sweep the floor", frequencyDays: 7, priority: .medium, estimatedMinutes: 15),
        TaskSuggestion(title: "Clean chair seats", frequencyDays: 14, priority: .low, estimatedMinutes: 10),
        TaskSuggestion(title: "Clean light fixtures", frequencyDays: 30, priority: .low, estimatedMinutes: 15)
    ]

    private static let general = [
        TaskSuggestion(title: "Tidy and put items away", frequencyDays: 7, priority: .medium, estimatedMinutes: 10),
        TaskSuggestion(title: "Dust surfaces", frequencyDays: 7, priority: .low, estimatedMinutes: 10),
        TaskSuggestion(title: "Vacuum or sweep the floor", frequencyDays: 7, priority: .medium, estimatedMinutes: 15),
        TaskSuggestion(title: "Empty the wastebasket", frequencyDays: 7, priority: .medium, estimatedMinutes: 5),
        TaskSuggestion(title: "Clean windows and mirrors", frequencyDays: 30, priority: .low, estimatedMinutes: 20)
    ]
}
