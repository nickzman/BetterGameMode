//
//  AppDelegate.swift
//  BetterGameMode
//
//  Created by Nick Zitzmann on 12/27/24.
//

import Cocoa
import os.log
import UserNotifications

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
	private enum IsGamePolicyCtlInstalled: Int {
		case unknown
		case notInstalled
		case installed
	}
	private enum GameModeEnablementPolicy: Int {
		case unknown
		case automatic
		case disabled
	}
	private enum IsGameModeEnabled: Int {
		case unknown
		case disabled
		case enabled
	}
	private var appLaunchedNotificationObserver: NSObjectProtocol?
	private var appTerminatedNotificationObserver: NSObjectProtocol?
	
	private var appsThatEnableGameMode: Set<NSRunningApplication> = []
	private var enablementPolicy: GameModeEnablementPolicy = .unknown
	private var gameMode: IsGameModeEnabled = .unknown
	private var gamePolicyCtlInstalled: IsGamePolicyCtlInstalled = .unknown
	private var prefsWindowController: NSWindowController?
	private var statusItem : NSStatusItem!
	
	// MARK: Application delegate
	
	func applicationDidFinishLaunching(_ aNotification: Notification) {
		let menu = NSMenu()
		
		// Set up the status item:
		self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
		self.statusItem.menu = menu
		self.statusItem.button?.image = NSImage.init(systemSymbolName: "gamecontroller.circle", accessibilityDescription: nil)
		menu.delegate = self
		
		// Ask the user if we can send them notifications:
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { (granted, error) in
		}
		// Install notifications for when apps are launched and terminated, if gamepolicyctl is installed:
		self.updateStateAndConditionallyInstallNotificationWatchers()
		// Also check to see if any currently launched apps should trigger Game Mode. Do this after registering the notification to reduce the chance of an app slipping through due to a race condition.
		for runningApp in NSWorkspace.shared.runningApplications {
			self.checkIfRunningApplicationShouldForceOnGameMode(runningApp: runningApp)
		}
	}
	
	func applicationWillTerminate(_ notification: Notification) {
		// This may or may not be necessary, but let's clean up after ourselves:
		if self.appLaunchedNotificationObserver != nil {
			NotificationCenter.default.removeObserver(self.appLaunchedNotificationObserver!)
		}
		
		if self.appTerminatedNotificationObserver != nil {
			NotificationCenter.default.removeObserver(self.appTerminatedNotificationObserver!)
		}
	}
	
	// MARK: Menu delegate
	
	func menuNeedsUpdate(_ menu: NSMenu) {
		updateStateAndConditionallyInstallNotificationWatchers()
		
		// Build the menu manually based on what running gamepolicyctl tells us:
		menu.removeAllItems()
		
		if self.gamePolicyCtlInstalled == .unknown {
			menu.addItem(withTitle: NSLocalizedString("MenuCantCheckStatus1", comment: ""), action: nil, keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuCantCheckStatus2", comment: ""), action: nil, keyEquivalent: "")
		}
		if self.gamePolicyCtlInstalled == .notInstalled {
			menu.addItem(withTitle: NSLocalizedString("MenuNoXcode1", comment: ""), action: nil, keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuNoXcode2", comment: ""), action: nil, keyEquivalent: "")
		} else {
			switch (self.enablementPolicy) {
			case .automatic:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyAutomatic", comment: ""), action: nil, keyEquivalent: "")
			case .unknown:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyUnknown", comment: ""), action: nil, keyEquivalent: "")
			case .disabled:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyManual", comment: ""), action: nil, keyEquivalent: "")
			}
			
			switch (self.gameMode) {
			case .unknown:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeUnknown", comment: ""), action: nil, keyEquivalent: "")
			case .enabled:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeOn", comment: ""), action: nil, keyEquivalent: "")
			case .disabled:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeOff", comment: ""), action: nil, keyEquivalent: "")
			}
			
			menu.addItem(NSMenuItem.separator())
			menu.addItem(withTitle: NSLocalizedString("MenuGameModeForceAutomatic", comment: ""), action: #selector(automaticallyEnableGameMode), keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuGameModeForceOn", comment: ""), action: #selector(enableGameMode), keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuGameModeForceOff", comment: ""), action: #selector(disableGameMode), keyEquivalent: "")
			menu.addItem(NSMenuItem.separator())
			menu.addItem(withTitle: NSLocalizedString("MenuPrefs", comment: ""), action: #selector(openPreferences), keyEquivalent: "")
			menu.addItem(NSMenuItem.separator())
		}
		menu.addItem(withTitle: NSLocalizedString("MenuQuit", comment: ""), action: #selector(quit), keyEquivalent: "")
	}
	
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(automaticallyEnableGameMode) {
			menuItem.state = self.enablementPolicy == .automatic ? .on : .off
		}
		if menuItem.action == #selector(enableGameMode) {
			menuItem.state = self.enablementPolicy == .disabled && self.gameMode == .enabled ? .on : .off
		}
		if menuItem.action == #selector(disableGameMode) {
			menuItem.state = self.enablementPolicy == .disabled && self.gameMode == .disabled ? .on : .off
		}
		return true
	}
	
	// MARK: Actions
	
	@objc func automaticallyEnableGameMode(_ sender: Any) {
		setGameModeEnablementPolicyString("auto")
	}
	
	@objc func disableGameMode(_ sender: Any) {
		setGameModeEnablementPolicyString("off")
	}
	
	@objc func enableGameMode(_ sender: Any) {
		setGameModeEnablementPolicyString("on")
	}
	
	@objc func openPreferences(_ sender: Any) {
		if self.prefsWindowController == nil {
			self.prefsWindowController = NSStoryboard.main?.instantiateController(withIdentifier: "PreferencesWindow") as? NSWindowController
		}
		
		NSApplication.shared.activate(ignoringOtherApps: true)
		if !(self.prefsWindowController?.window?.isVisible ?? false) {
			self.prefsWindowController?.window!.center()
			self.prefsWindowController?.window!.makeKeyAndOrderFront(sender)
		} else if self.prefsWindowController?.window != nil {
			self.prefsWindowController?.window!.makeKeyAndOrderFront(sender)
		}
	}
	
	@objc func quit(_ sender: Any) {
		NSApplication.shared.terminate(sender)
	}
	
	// MARK: Internal
	
	private func checkIfRunningApplicationShouldForceOnGameMode(runningApp: NSRunningApplication!) {
		if UserDefaults.standard.bool(forKey: PrefsViewController.forceGameModeKey) {	// is Force Game Mode On enabled?
			if let appBundleIDsThatForceOn = UserDefaults.standard.array(forKey: PrefsViewController.appBundleIDsThatForceOnKey) as? [String] {	// and we have app bundle IDs that will trigger game mode on if launched?
				if let bundleID = runningApp.bundleIdentifier {
					if appBundleIDsThatForceOn.contains(bundleID) {	// and this is one of those apps?
						if self.gameMode != .enabled {	// if it's not enabled, let's enable it and tell the user we enabled it
							let notificationContent = UNMutableNotificationContent()
							
							notificationContent.title = NSLocalizedString("GameModeForcedOnTitle", comment: "")
							notificationContent.body = String(format: NSLocalizedString("GameModeForcedOnSubtitle", comment: ""), runningApp.localizedName ?? "?")
							
							let notification = UNNotificationRequest(identifier: "GameModeOn", content: notificationContent, trigger: nil)
							
							UNUserNotificationCenter.current().add(notification)
							self.setGameModeEnablementPolicyString("on")
							self.enablementPolicy = .disabled	// assume the above worked & update our state accordingly
							self.gameMode = .enabled
						}
						self.appsThatEnableGameMode.insert(runningApp)
					}
				}
			}
		}
	}
	
	private func checkIfTerminatedApplicationShouldRevertToAutomaticGameMode(terminatedApp: NSRunningApplication!) {
		if self.appsThatEnableGameMode.contains(terminatedApp) {	// and we previously forced game mode on because this app launched?
			self.appsThatEnableGameMode.remove(terminatedApp)
			if self.appsThatEnableGameMode.isEmpty && UserDefaults.standard.bool(forKey: PrefsViewController.turnGameModeBackToAutomaticKey) {	// if that was the last app launched that forced game mode on, and the user set the preference to switch it back to automatic, then let's do that
				let notificationContent = UNMutableNotificationContent()
				
				notificationContent.title = NSLocalizedString("GameModeForcedAutomaticTitle", comment: "")
				notificationContent.body = String(format: NSLocalizedString("GameModeForcedAutomaticSubtitle", comment: ""), terminatedApp.localizedName ?? "?")
				
				let notification = UNNotificationRequest(identifier: "GameModeOff", content: notificationContent, trigger: nil)
				
				UNUserNotificationCenter.current().add(notification)
				self.setGameModeEnablementPolicyString("auto")
				self.enablementPolicy = .automatic
				self.gameMode = .disabled
			}
		}
	}
	
	private func gamePolicyCtlStatus() -> (isInstalled: IsGamePolicyCtlInstalled, gameMode: IsGameModeEnabled, enablementPolicy: GameModeEnablementPolicy) {
		let process = Process()
		let pipe = Pipe()
		let fileHandle = pipe.fileHandleForReading
		
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		process.arguments = ["gamepolicyctl", "game-mode", "status"]
		process.standardOutput = pipe
		process.standardError = pipe
		process.launch()
		process.waitUntilExit()
		
		let output: Data?
		
		do {
			output = try fileHandle.readToEnd()
		} catch {
			Logger().error("Failed to read output from gamepolicyctl due to an error: \(error)")
			return (.unknown, .unknown, .unknown)
		}
		guard let outputString = String(data: output ?? Data(), encoding: .utf8) else {
			return (.unknown, .unknown, .unknown)
		}
		var gameMode: IsGameModeEnabled = .unknown
		var enablementPolicy: GameModeEnablementPolicy = .unknown
		
		if outputString.contains("xcrun: error: unable to find utility") {	// unable to find - not installed
			return (.notInstalled, .unknown, .unknown)
		}
		
		do {
			if outputString.contains(try Regex("Game mode is(.+)off")) {
				gameMode = .disabled
			} else if outputString.contains(try Regex("Game mode is(.+)on")) {
				gameMode = .enabled
			}
		} catch {
			gameMode = .disabled
		}
		
		if outputString.contains("Game mode enablement policy is currently automatic") {
			enablementPolicy = .automatic
		} else if outputString.contains("Game mode enablement policy is currently disabled") {
			enablementPolicy = .disabled
		}
		return (.installed, gameMode, enablementPolicy)
	}
	
	private func setGameModeEnablementPolicyString(_ policyString: String!) {
		let process = Process()
		let pipe = Pipe()
		let fileHandle = pipe.fileHandleForReading
		
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		process.arguments = ["gamepolicyctl", "game-mode", "set", policyString]
		process.standardOutput = pipe
		process.standardError = pipe
		process.launch()
		process.waitUntilExit()
		
		let output: Data?
		
		do {
			output = try fileHandle.readToEnd()
		} catch {
			output = nil
		}
		guard let outputString = String(data: output ?? Data(), encoding: .utf8) else {
			return
		}
	}
	
	private func updateStateAndConditionallyInstallNotificationWatchers() {
		let status = gamePolicyCtlStatus()
		
		if (status.isInstalled == .installed) {
			weak var weakSelf = self
			
			if appLaunchedNotificationObserver == nil {
				self.appLaunchedNotificationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil) { aNotification in
					if let runningApp = aNotification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {	// sanity check - this is an NSRunningApplication, right?
						if let strongSelf = weakSelf {
							strongSelf.checkIfRunningApplicationShouldForceOnGameMode(runningApp: runningApp)
						}
					} else {
						Logger().error("Error! NSWorkspace.applicationUserInfoKey was not an NSRunningApplication for some reason.")
					}
				}
			}
			
			if appTerminatedNotificationObserver == nil {
				self.appTerminatedNotificationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { aNotification in
					if let terminatedApp = aNotification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {	// sanity check - this is an NSRunningApplication, right?
						if let strongSelf = weakSelf {
							strongSelf.checkIfTerminatedApplicationShouldRevertToAutomaticGameMode(terminatedApp: terminatedApp)
						}
					} else {
						Logger().error("Error! NSWorkspace.applicationUserInfoKey was not an NSRunningApplication for some reason.")
					}
				}
			}
		} else {	// if it's not installed, but the notifications are on, then remove them
			if self.appLaunchedNotificationObserver != nil {
				NSWorkspace.shared.notificationCenter.removeObserver(self.appLaunchedNotificationObserver as Any)
				self.appLaunchedNotificationObserver = nil
			}
			
			if self.appTerminatedNotificationObserver != nil {
				NSWorkspace.shared.notificationCenter.removeObserver(self.appTerminatedNotificationObserver as Any)
				self.appTerminatedNotificationObserver = nil
			}
		}
		self.gamePolicyCtlInstalled = status.isInstalled
		self.gameMode = status.gameMode
		self.enablementPolicy = status.enablementPolicy
	}
}

