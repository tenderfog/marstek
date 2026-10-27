import SwiftUI

@MainActor
struct VenusMiniOutageTimeline: View {
    @ObservedObject var store: VenusOutagesStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Group {
                if store.selection == nil { setup }
                else { configured(at: context.date) }
            }
            .frame(width: 300, height: store.selection == nil ? 30 : 58)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(at: context.date))
        }
    }

    private var setup: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.slash").font(.system(size: 11, weight: .medium))
            Text("Графік відключень").font(.system(size: 11, weight: .medium))
            Spacer(minLength: 4)
            Text("Додати адресу").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }.foregroundStyle(.white.opacity(0.7))
    }

    private func configured(at now: Date) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text("За графіком · \(planSummary(at: now))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VenusOutageStyle.color(store.currentPlanState))
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Text("Зараз \(clock(now))").font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }.frame(height: 16)
            VStack(spacing: 2) {
                track(at: now).frame(height: 18)
                HStack(spacing: 0) {
                    Text("00"); Spacer(); Text("06"); Spacer(); Text("12"); Spacer(); Text("18"); Spacer(); Text("24")
                }.font(.system(size: 8)).monospacedDigit().foregroundStyle(.white.opacity(0.35)).frame(height: 10)
            }.frame(height: 30)
        }
    }

    private func track(at now: Date) -> some View {
        Canvas { context, size in
            let bar = CGRect(x: 0, y: 5.5, width: size.width, height: 7)
            let outline = Path(roundedRect: bar, cornerRadius: 3.5)
            var strip = context
            strip.clip(to: outline)
            strip.fill(outline, with: .color(.white.opacity(0.055)))
            for interval in store.todaySlots {
                let x = size.width * Double(interval.start) / 1440
                let width = size.width * Double(interval.end - interval.start) / 1440
                let color: Color
                switch interval.state {
                case .noOutagePlanned: color = VenusOutageStyle.color(.noOutagePlanned).opacity(0.8)
                case .outagePlanned: color = VenusOutageStyle.color(.outagePlanned).opacity(0.85)
                case .emergency: color = VenusOutageStyle.color(.emergency).opacity(0.55)
                case .unknown: color = .white.opacity(0.07)
                case .stale: color = .white.opacity(0.18)
                }
                strip.fill(Path(CGRect(x: x, y: bar.minY, width: width, height: bar.height)), with: .color(color))
            }
            let minute = Double(VenusOutagesReport.minute(at: now))
            let x = size.width * minute / 1440
            var marker = Path()
            marker.move(to: CGPoint(x: x, y: 1.5)); marker.addLine(to: CGPoint(x: x, y: 17))
            context.stroke(marker, with: .color(.white.opacity(0.95)), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: 0, width: 3.6, height: 3.6)), with: .color(.white))
        }
    }

    private func planSummary(at now: Date) -> String {
        let minute = VenusOutagesReport.minute(at: now)
        let end = store.todaySlots.first { $0.start <= minute && minute < $0.end }.map { VenusOutageInterval.time($0.end) }
        switch store.currentPlanState {
        case .noOutagePlanned: return end.map { "без відключень до \($0)" } ?? "без відключень"
        case .outagePlanned: return end.map { "відключення до \($0)" } ?? "планове відключення"
        case .emergency: return "аварійні відключення"
        case .stale: return "потрібне оновлення"
        case .unknown: return store.isLoading ? "оновлюємо дані" : "ще немає даних"
        }
    }

    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = VenusOutagesReport.kyivCalendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func accessibilityText(at now: Date) -> String {
        guard store.selection != nil else { return "Графік відключень не налаштований. Додай адресу в головній панелі." }
        return "Графік на сьогодні, київський час. Зараз \(clock(now)). \(store.statusLabel). \(store.isCached ? "Збережений графік. " : "")Біла позначка показує поточний час. Це план оператора, не фактична наявність електрики."
    }
}

@MainActor
struct VenusTodayOutageCard: View {
    @ObservedObject var store: VenusOutagesStore
    let onOpen: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            Button(action: onOpen) { content }
                .buttonStyle(.plain)
                .padding(11).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 17))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "bolt.slash").font(.system(size: 12, weight: .medium))
                Text("Сьогодні").font(.system(size: 13, weight: .semibold))
                if let selection = store.selection {
                    Text("· \(selection.group)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 4)
                Text(store.statusLabel)
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .foregroundStyle(VenusOutageStyle.color(store.currentPlanState))
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
            }.foregroundStyle(.white.opacity(0.85))
            if store.selection == nil {
                Text("Налаштувати графік для своєї адреси")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            } else {
                intervals
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var intervals: some View {
        if store.report == nil {
            Text(store.error ?? "Часові інтервали з’являться після відповіді оператора")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
        } else if store.currentPlanState == .emergency {
            Text("Екстрені відключення: погодинний план може не діяти.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
        } else if !store.nextIntervals(limit: 3).isEmpty {
            HStack(spacing: 7) {
                ForEach(store.nextIntervals(limit: 3)) { interval in
                    let state = displayState(interval.state)
                    HStack(spacing: 4) {
                        Image(systemName: VenusOutageStyle.symbol(state)).font(.system(size: 8, weight: .semibold))
                        Text(interval.timeRange).monospacedDigit()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(VenusOutageStyle.color(state))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(VenusOutageStyle.color(state).opacity(0.09), in: Capsule())
                    .help("\(interval.timeRange) · \(interval.state.label). За графіком, не фактична наявність живлення.")
                }
                Spacer(minLength: 0)
            }
        } else if let error = store.error {
            Text(error).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
        } else {
            Text("Точні інтервали ще недоступні")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
    }

    private func displayState(_ state: VenusOutagePlanState) -> VenusOutagePlanState {
        switch store.currentPlanState {
        case .stale, .emergency, .unknown: return store.currentPlanState
        case .noOutagePlanned, .outagePlanned: return state
        }
    }
}

@MainActor
struct VenusOutagesSettings: View {
    @ObservedObject var store: VenusOutagesStore
    let onBack: () -> Void
    @State private var cityQuery = ""
    @State private var streetQuery = ""
    @State private var houseQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Button(action: onBack) { Label("Назад", systemImage: "chevron.left") }
                    .buttonStyle(VenusButtonStyle())
                Text("Графіки відключень").font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.selection != nil { savedSchedule }
                    addressForm
                    if let error = store.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if store.isLoading || store.isSearching {
                        Text(store.isSearching ? "Шукаємо в офіційному переліку…" : "Оновлюємо графік…")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                    HStack(spacing: 7) {
                        Link("Джерело ↗", destination: store.sourceURL)
                        Text("План оператора, не фактичне живлення.")
                            .foregroundStyle(.white.opacity(0.45))
                    }.font(.system(size: 10))
                }.padding(.vertical, 2).padding(.trailing, 3)
            }.scrollIndicators(.automatic)
        }
        .padding(22).frame(width: 520, height: 610)
        .foregroundStyle(.white).background(.clear).preferredColorScheme(.dark)
        .onAppear {
            store.loadRegions()
            if cityQuery.isEmpty { cityQuery = store.selectedCity?.name ?? "" }
            if streetQuery.isEmpty { streetQuery = store.selectedStreet?.name ?? "" }
            if houseQuery.isEmpty { houseQuery = store.selectedHouse?.name ?? "" }
        }
    }

    private var addressForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.selection != nil {
                Button("Змінити адресу") {
                    store.clearSelection(); cityQuery = ""; streetQuery = ""; houseQuery = ""
                }.buttonStyle(VenusButtonStyle())
            } else {
                Text("Адреса для графіка").font(.system(size: 15, weight: .semibold))
                Text("Обери місто й оператора, потім введи вулицю та будинок.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                regionMenu
                if store.regions.isEmpty && !store.isSearching {
                    Button("Спробувати ще раз", action: store.loadRegions).buttonStyle(VenusButtonStyle())
                }
                if store.selectedRegion != nil { dsoMenu }
                if store.selectedDSO != nil {
                    if store.selectedRegion?.hasCities == true { citySearch }
                    if store.selectedRegion?.hasCities != true || store.selectedCity != nil { addressSearch }
                    if store.selectedHouse != nil { groupSelection }
                }
            }
        }
    }

    private var regionMenu: some View {
        Menu {
            ForEach(store.regions) { region in
                Button(region.name) {
                    store.selectRegion(region); cityQuery = ""; streetQuery = ""; houseQuery = ""
                }
            }
        } label: { selectionLabel(store.selectedRegion?.name ?? "Обрати область") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).disabled(store.regions.isEmpty)
    }

    private var dsoMenu: some View {
        Menu {
            ForEach(store.dsos) { dso in
                Button(dso.name) {
                    store.selectDSO(dso); cityQuery = ""; streetQuery = ""; houseQuery = ""
                }
            }
        } label: { selectionLabel(store.selectedDSO?.name ?? "Обрати оператора") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).disabled(store.dsos.isEmpty)
    }

    private var citySearch: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Місто", text: $cityQuery).textFieldStyle(VenusTextFieldStyle())
                .onChange(of: cityQuery) { query in
                    if query != store.selectedCity?.name { store.searchCities(query) }
                }
            if let selected = store.selectedCity { selectionSummary(selected.name) }
            else {
                ForEach(store.cities) { item in
                    addressResult(item, selected: false) {
                        store.selectCity(item); cityQuery = item.name; streetQuery = ""; houseQuery = ""
                    }
                }
            }
        }
    }

    private var addressSearch: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Вулиця").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 5) {
                    TextField("Назва вулиці", text: $streetQuery)
                        .textFieldStyle(VenusTextFieldStyle())
                        .onChange(of: streetQuery) { query in
                            if query != store.selectedStreet?.name {
                                store.searchStreets(query)
                                houseQuery = ""
                            }
                        }
                    if !streetQuery.isEmpty {
                        Button { streetQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15)).foregroundStyle(.white.opacity(0.5))
                                .frame(width: 28, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Очистити вулицю")
                    }
                }
                if store.selectedStreet == nil && !store.streets.isEmpty {
                    addressSuggestions(store.streets) { item in
                        store.selectStreet(item); streetQuery = item.name; houseQuery = store.houseHint ?? ""
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 7) {
                Text("Будинок").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                TextField("№", text: $houseQuery)
                    .textFieldStyle(VenusTextFieldStyle())
                    .disabled(store.selectedStreet == nil)
                    .opacity(store.selectedStreet == nil ? 0.45 : 1)
                    .onChange(of: houseQuery) { query in
                        if store.selectedStreet != nil && query != store.selectedHouse?.name {
                            store.searchHouses(query)
                        }
                    }
                if store.selectedStreet != nil && store.selectedHouse == nil && !store.houses.isEmpty {
                    addressSuggestions(store.houses) { item in
                        store.selectHouse(item); houseQuery = item.name
                    }
                }
            }.frame(width: 104, alignment: .topLeading)
        }
    }

    private func addressSuggestions(_ items: [VenusOutageAddressItem], select: @escaping (VenusOutageAddressItem) -> Void) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    Button { select(item) } label: {
                        Text(item.name).font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(store.isSearching)
                    if item.id != items.last?.id { Divider().overlay(.white.opacity(0.06)).padding(.horizontal, 12) }
                }
            }
        }.frame(height: min(CGFloat(items.count) * 45, 180))
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var groupSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Підтвердь групу").font(.system(size: 14, weight: .semibold))
            ForEach(store.groups, id: \.self) { group in
                Button { store.selectGroup(group) } label: {
                    HStack { Text("Зберегти групу \(group)"); Spacer(); Image(systemName: "checkmark") }
                        .frame(maxWidth: .infinity)
                }.buttonStyle(VenusButtonStyle(primary: true)).disabled(store.isLoading)
            }
        }
    }

    private var savedSchedule: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selection = store.selection {
                Text(selection.addressLabel).font(.system(size: 14, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Група \(selection.group)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            HStack {
                Text(store.statusLabel).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VenusOutageStyle.color(store.currentPlanState))
                Spacer()
                Button("Оновити", action: store.refresh).buttonStyle(VenusButtonStyle()).disabled(store.isLoading)
            }
            if let fetched = store.fetchedAt {
                Text("\(store.isCached ? "Останній графік" : "Отримано") · \(fetched.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            if store.currentPlanState == .emergency {
                Text("Під час екстрених відключень наведений погодинний графік може не діяти.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            }
            if store.report != nil && !store.todaySlots.isEmpty {
                Text("Сьогодні · за київським часом").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                ForEach(store.todaySlots) { interval in
                    HStack(spacing: 10) {
                        Text(interval.timeRange).monospacedDigit().frame(width: 110, alignment: .leading)
                        Image(systemName: VenusOutageStyle.symbol(intervalState(interval.state))).frame(width: 17)
                        Text(interval.state.label)
                        Spacer(minLength: 0)
                    }.font(.system(size: 12)).foregroundStyle(VenusOutageStyle.color(intervalState(interval.state)))
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private func intervalState(_ state: VenusOutagePlanState) -> VenusOutagePlanState {
        switch store.currentPlanState {
        case .stale, .emergency, .unknown: return store.currentPlanState
        case .noOutagePlanned, .outagePlanned: return state
        }
    }

    private func selectionLabel(_ title: String) -> some View {
        HStack { Text(title).font(.system(size: 13)).lineLimit(1); Spacer(); Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)) }
            .foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 13).frame(minHeight: 44)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
    }

    private func selectionSummary(_ title: String) -> some View {
        Label("Обрано: \(title)", systemImage: "checkmark")
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func addressResult(_ item: VenusOutageAddressItem, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(item.name); Spacer(); Image(systemName: selected ? "checkmark" : "chevron.right") }
                .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(VenusButtonStyle()).disabled(store.isSearching)
    }
}

private enum VenusOutageStyle {
    static func color(_ state: VenusOutagePlanState) -> Color {
        switch state {
        case .noOutagePlanned: return Color(red: 0.4, green: 0.84, blue: 0.58)
        case .outagePlanned: return Color(red: 0.96, green: 0.49, blue: 0.4)
        case .emergency: return Color(red: 1, green: 0.65, blue: 0.37)
        case .unknown, .stale: return .white.opacity(0.5)
        }
    }

    static func symbol(_ state: VenusOutagePlanState) -> String {
        switch state {
        case .noOutagePlanned: return "checkmark"
        case .outagePlanned: return "bolt.slash"
        case .emergency: return "exclamationmark.triangle"
        case .unknown: return "questionmark"
        case .stale: return "clock"
        }
    }
}
