//
//  PrefsViewController.swift
//  BetterGameMode
//
//  Created by Nick Zitzmann on 12/27/24.
//

import Cocoa

class PrefsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	public static let appBundleIDsThatForceOnKey = "AppBundleIDsThatForceOn"
	public static let forceGameModeKey = "ForceGameMode"
	public static let turnGameModeBackToAutomaticKey = "TurnGameModeBackToAutomatic"
	
	@IBOutlet weak var addApplicationButton: NSButton!
	@IBOutlet weak var appsThatForceOnTableView: NSTableView!
	@IBOutlet weak var forceGameModeSwitch: NSSwitch!
	@IBOutlet weak var launchOnLoginSwitch: NSSwitch!
	@IBOutlet weak var removeApplicationButton: NSButton!
	@IBOutlet weak var turnGameModeBackToAutomaticSwitch: NSSwitch!
	
	private var appBundleIDsThatForceOn: [String] = []
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		// Update the UI to reflect the user defaults:
		self.forceGameModeSwitch.state = UserDefaults.standard.bool(forKey: PrefsViewController.forceGameModeKey) ? .on : .off
		self.turnGameModeBackToAutomaticSwitch.state = UserDefaults.standard.bool(forKey: PrefsViewController.turnGameModeBackToAutomaticKey) ? .on : .off
		self.appBundleIDsThatForceOn = UserDefaults.standard.array(forKey: PrefsViewController.appBundleIDsThatForceOnKey) as? [String] ?? []
		self.appsThatForceOnTableView.reloadData()
		
		// Disable controls for preferences that don't do anything if force gaming mode isn't on:
		self.turnGameModeBackToAutomaticSwitch.isEnabled = self.forceGameModeSwitch.state == .on
		self.appsThatForceOnTableView.isEnabled = self.forceGameModeSwitch.state == .on
		self.addApplicationButton.isEnabled = self.forceGameModeSwitch.state == .on
	}
	
	// MARK: Table view data source
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		return self.appBundleIDsThatForceOn.count
	}
	
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let cell = tableView.makeView(withIdentifier: tableColumn!.identifier, owner: nil) as! NSTableCellView
		let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: self.appBundleIDsThatForceOn[row])
		
		if appURL != nil {	// is the app installed, according to Launch Services?
			let bundle = Bundle(url: appURL!)
			
			cell.imageView?.image = NSWorkspace.shared.icon(forFile: appURL!.path)
			if bundle != nil {
				cell.textField?.stringValue = (bundle!.localizedInfoDictionary?[String(kCFBundleNameKey)] as? String ?? "")
			}
			cell.textField?.stringValue = appURL!.lastPathComponent
		} else {	// if not, then just print the bundle ID so the user can at least delete it
			cell.imageView?.image = nil
			cell.textField?.stringValue = "(\(self.appBundleIDsThatForceOn[row]))"
		}
		return cell
	}
	
	// MARK: Table view delegate
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		self.removeApplicationButton.isEnabled = self.appsThatForceOnTableView.selectedRowIndexes.count > 0	// the remove button needs something selected for it to work
	}
	
	// MARK: Actions
	
	@IBAction func addApplicationAction(_ sender: Any) {
		let openPanel = NSOpenPanel()
		
		openPanel.allowsMultipleSelection = false
		openPanel.allowedContentTypes = [.application]
		openPanel.beginSheetModal(for: self.view.window!) { result in
			if result == .OK {
				let appURL = openPanel.url!
				if let appBundle = Bundle(url: appURL) {	// we need to load the app's bundle identifier
					if let appBundleIdentifier = appBundle.bundleIdentifier {
						self.appBundleIDsThatForceOn.append(appBundleIdentifier)
						self.appsThatForceOnTableView.insertRows(at: IndexSet(integer: self.appBundleIDsThatForceOn.count - 1), withAnimation: .effectFade)
						UserDefaults.standard.set(self.appBundleIDsThatForceOn, forKey: PrefsViewController.appBundleIDsThatForceOnKey)
					}
				}
			}
		}
	}
	
	// MARK: Actions
	
	@IBAction func forceGameModeAction(_ sender: Any) {
		if self.forceGameModeSwitch.state == .on {
			UserDefaults.standard.set(true, forKey: PrefsViewController.forceGameModeKey)
			self.turnGameModeBackToAutomaticSwitch.isEnabled = true
			self.appsThatForceOnTableView.isEnabled = true
			self.addApplicationButton.isEnabled = true
			self.removeApplicationButton.isEnabled = self.appsThatForceOnTableView.selectedRow >= 0
		} else {	// disable all controls for things that don't do anything if this setting is disabled
			UserDefaults.standard.set(false, forKey: PrefsViewController.forceGameModeKey)
			self.turnGameModeBackToAutomaticSwitch.isEnabled = false
			self.appsThatForceOnTableView.isEnabled = false
			self.addApplicationButton.isEnabled = false
			self.removeApplicationButton.isEnabled = false
		}
	}
	
	@IBAction func launchOnLoginAction(_ sender: Any) {
		// TODO: Fill in here
	}
	
	@IBAction func removeApplicationAction(_ sender: Any) {
		let selectedRow = self.appsThatForceOnTableView.selectedRow
		
		if selectedRow >= 0 {	// sanity check: don't crash if nothing is selected
			self.appBundleIDsThatForceOn.remove(at: selectedRow)
			self.appsThatForceOnTableView.removeRows(at: IndexSet(integer: selectedRow), withAnimation: .effectFade)
			UserDefaults.standard.set(self.appBundleIDsThatForceOn, forKey: PrefsViewController.appBundleIDsThatForceOnKey)
		}
	}
	
	@IBAction func turnGameModeBackToAutomaticAction(_ sender: Any) {
		UserDefaults.standard.set(self.turnGameModeBackToAutomaticSwitch.state == .on ? true : false, forKey: PrefsViewController.turnGameModeBackToAutomaticKey)
	}
}

