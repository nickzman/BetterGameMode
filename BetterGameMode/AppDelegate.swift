//
//  AppDelegate.swift
//  BetterGameMode
//
//  Created by Nick Zitzmann on 12/27/24.
//

import Cocoa
import os.log

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
	
	private var enablementPolicy: GameModeEnablementPolicy = .unknown
	private var gameMode: IsGameModeEnabled = .unknown
	private var gamePolicyCtlInstalled: IsGamePolicyCtlInstalled = .unknown
	private var statusItem : NSStatusItem!
	
	func applicationDidFinishLaunching(_ aNotification: Notification) {
		let menu = NSMenu()
		
		// Set up the status item:
		self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
		self.statusItem.menu = menu
		self.statusItem.button?.image = NSImage.init(systemSymbolName: "gamecontroller.circle", accessibilityDescription: nil)
		menu.delegate = self
	}
	
	func menuNeedsUpdate(_ menu: NSMenu) {
		let status = gamePolicyCtlStatus()
		
		self.gamePolicyCtlInstalled = status.isInstalled
		self.gameMode = status.gameMode
		self.enablementPolicy = status.enablementPolicy
		
		// Build the menu manually based on what running gamepolicyctl tells us:
		menu.removeAllItems()
		
		if status.isInstalled == .unknown {
			menu.addItem(withTitle: "Failed to Check on Game Mode Status", action: nil, keyEquivalent: "")
			menu.addItem(withTitle: "Check Console.app for details.", action: nil, keyEquivalent: "")
		}
		if status.isInstalled == .notInstalled {
			menu.addItem(withTitle: "Xcode is Not Installed", action: nil, keyEquivalent: "")
			menu.addItem(withTitle: "Sorry, but this app requires Xcode to be installed in order to work.", action: nil, keyEquivalent: "")
		} else {
			switch (status.enablementPolicy) {
			case .automatic:
				menu.addItem(withTitle: "Current Game Mode Enablement Policy: Automatic", action: nil, keyEquivalent: "")
			case .unknown:
				menu.addItem(withTitle: "Unable to Determine Game Mode Enablement Policy", action: nil, keyEquivalent: "")
			case .disabled:
				menu.addItem(withTitle: "Current Game Mode Enablement Policy: Manual", action: nil, keyEquivalent: "")
			}
			
			switch (status.gameMode) {
			case .unknown:
				menu.addItem(withTitle: "Unable to Determine Game Mode Status", action: nil, keyEquivalent: "")
			case .enabled:
				menu.addItem(withTitle: "Game Mode: On", action: nil, keyEquivalent: "")
			case .disabled:
				menu.addItem(withTitle: "Game Mode: Off or Paused", action: nil, keyEquivalent: "")
			}
			
			menu.addItem(NSMenuItem.separator())
			menu.addItem(withTitle: "Automatically Enable Game Mode (default)", action: #selector(automaticallyEnableGameMode), keyEquivalent: "")
			menu.addItem(withTitle: "Force Enable Game Mode", action: #selector(enableGameMode), keyEquivalent: "")
			menu.addItem(withTitle: "Force Disable Game Mode", action: #selector(disableGameMode), keyEquivalent: "")
			menu.addItem(NSMenuItem.separator())
		}
		menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: ""))
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
	
	@objc func automaticallyEnableGameMode(_ sender: Any) {
		setGameModeEnablementPolicyString("auto")
	}
	
	@objc func disableGameMode(_ sender: Any) {
		setGameModeEnablementPolicyString("off")
	}
	
	@objc func enableGameMode(_ sender: Any) {
		setGameModeEnablementPolicyString("on")
	}
	
	@objc func quit(_ sender: Any) {
		NSApplication.shared.terminate(sender)
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
		
		if outputString.contains("Game mode is \u{1B}[0;31moff") {
			gameMode = .disabled
		} else if outputString.contains("Game mode is \u{1B}[0;32mon") {
			gameMode = .enabled
		}
		
		if outputString.contains("Game mode enablement policy is currently automatic") {
			enablementPolicy = .automatic
		} else if outputString.contains("Game mode enablement policy is currently disabled") {
			enablementPolicy = .disabled
		}
		return (.installed, gameMode, enablementPolicy)
	}
}

