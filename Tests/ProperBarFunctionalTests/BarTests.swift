import ApplicationServices
import Testing

@Suite(.serialized, .enabled(if: appBinary != nil, "run scripts/functional-test.sh"))
struct BarTests {
    @Test func launcherOpensAndClosesFromTheStartButton() async throws {
        let app = try await DemoApp()
        let start = try #require(app.element("start-button"))

        start.perform(kAXPressAction)
        #expect(await eventually { app.hasSearchField })

        start.perform(kAXPressAction)
        #expect(await eventually { !app.hasSearchField })
    }

    @Test func settingsStayInFrontWhenClickedWithTheLauncherOpen() async throws {
        let app = try await DemoApp()
        let start = try #require(app.element("start-button"))
        start.perform(kAXPressAction)
        try #require(await waitFor { app.labeled("Réglages de ProperBar") }).perform(kAXPressAction)
        let settings = try #require(await waitFor { app.window(titled: "Réglages de ProperBar") })

        let other = try await DemoApp(idle: true)
        try #require(await eventually { !app.isFrontmost })
        start.perform(kAXPressAction)
        try #require(await eventually { app.hasSearchField && app.isFrontmost })
        let titleBar = CGPoint(x: settings.frame.midX, y: settings.frame.minY + 12)
        try #require(app.owns(titleBar), "Settings is under another window")

        await click(at: titleBar)

        #expect(await eventually { !app.hasSearchField })
        try await Task.sleep(for: .milliseconds(500))
        #expect(app.isFrontmost, "the launcher handed focus back to the other app, burying Settings")
        #expect(app.window(titled: "Réglages de ProperBar") != nil)
        withExtendedLifetime(other) {}
    }

    @Test func tileMarginWidensDockTilesPastTheBarHeight() async throws {
        let app = try await DemoApp(["--demo-mode", "dock"])
        let before = try #require(app.element("tile")).frame.width

        app.element("start-button")?.perform(kAXPressAction)
        try #require(await waitFor { app.labeled("Réglages de ProperBar") }).perform(kAXPressAction)
        let slider = try #require(await waitFor { app.labeled("Marge autour des icônes") })
        let margin = try #require(slider.number)
        for _ in 0..<20 where (slider.number ?? .infinity) < 20 { slider.perform(kAXIncrementAction) }

        let added = (slider.number ?? margin) - margin
        #expect(await eventually { (app.element("tile")?.frame.width ?? 0) == before + added },
                "tile width \(app.element("tile")?.frame.width ?? 0), expected \(before + added)")
        #expect(before + added > mainBar(app).height - 8, "the margin must push the tile past the old square cap")
    }

    @Test func showDesktopCornerSitsAtTheBottomRightCorner() async throws {
        let app = try await DemoApp()
        let corner = try #require(app.element("show-desktop")).frame
        // The bar sits above a visible system Dock, so its own bottom-right corner is the target, not the screen's.
        let bar = mainBar(app)
        #expect(bar.maxX == mainScreen.maxX, "the bar \(bar) does not span \(mainScreen)")
        #expect(corner.contains(CGPoint(x: bar.maxX - 1, y: bar.maxY - 1)), "\(corner) misses the corner of \(bar)")
    }

    private func mainBar(_ app: DemoApp) -> CGRect {
        let start = app.element("start-button")?.frame.center ?? .zero
        return app.windows.map(\.frame).first { $0.contains(start) } ?? .zero
    }
}
