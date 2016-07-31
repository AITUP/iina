//
//  MainWindow.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MainWindow: NSWindowController, NSWindowDelegate {
  
  let ud: UserDefaults = UserDefaults.standard
  
  var playerController: PlayerController!
  lazy var videoView: VideoView! = self.initVideoView()
  
  var mousePosRelatedToWindow: CGPoint?
  var isDragging: Bool = false
  
  var isInFullScreen: Bool = false
  
  override var windowNibName: String {
    return "MainWindow"
  }
  
  var fadeableViews: [NSView?] = []
  
  /** Animation state of he hide/show part */
  enum UIAnimationState {
    case shown, hidden, willShow, willHide
  }
  
  var animationState: UIAnimationState = .shown
  
  var osdAnimationState: UIAnimationState = .hidden
  
  /** For auto hiding ui after a timeout */
  var hideControlTimer: Timer?
  
  var hideOSDTimer: Timer?
  
  /** The index of current speed in speed value array */
  var speedValueIndex: Int = 5
  
  enum ScrollDirection {
    case horizontal
    case vertical
  }
  
  var scrollDirection: ScrollDirection?
  
  /** The quick setting window */
  lazy var quickSettingPanel: QuickSettingPanel = {
    let panel = QuickSettingPanel()
    panel.playerController = self.playerController
    return panel
  }()
  
  @IBOutlet weak var titleBarView: NSVisualEffectView!
  @IBOutlet weak var titleBarTitleCell: NSTextFieldCell!
  @IBOutlet weak var controlBar: ControlBarView!
  @IBOutlet weak var playButton: NSButton!
  @IBOutlet weak var playSlider: NSSlider!
  @IBOutlet weak var volumeSlider: NSSlider!
  @IBOutlet weak var muteButton: NSButton!
  
  @IBOutlet weak var rightLabel: NSTextField!
  @IBOutlet weak var leftLabel: NSTextField!
  @IBOutlet weak var leftArrowLabel: NSTextField!
  @IBOutlet weak var rightArrowLabel: NSTextField!
  @IBOutlet weak var osd: NSTextField!

  override func windowDidLoad() {
    super.windowDidLoad()
    guard let w = self.window else { return }
    w.titleVisibility = .hidden;
    w.styleMask.insert(NSFullSizeContentViewWindowMask);
    w.titlebarAppearsTransparent = true
    // need to deal with control bar, so handle it manually
    // w.isMovableByWindowBackground  = true
    // set background color to black
    w.backgroundColor = NSColor.black()
    updateTitle()
    if #available(OSX 10.11, *), UserDefaults.standard.bool(forKey: Preference.Key.controlBarDarker) {
      titleBarView.material = .ultraDark
    }
    // size
    w.minSize = NSMakeSize(500, 300)
    // fade-able views
    withStandardButtons { button in
      self.fadeableViews.append(button)
    }
    fadeableViews.append(titleBarView)
    fadeableViews.append(controlBar)
    guard let cv = w.contentView else { return }
    cv.addTrackingArea(NSTrackingArea(rect: cv.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: nil))
    // video view
    cv.addSubview(videoView, positioned: .below, relativeTo: nil)
    playerController.startMPVOpenGLCB(videoView)
    // other initialization
    osd.isHidden = true
    leftArrowLabel.isHidden = true
    rightArrowLabel.isHidden = true
    // make main
    w.makeMain()
    w.makeKeyAndOrderFront(nil)
    w.setIsVisible(false)
  }
  
  // MARK: - Lazy initializers
  
  func initVideoView() -> VideoView {
    let v = VideoView(frame: window!.contentView!.bounds)
    return v
  }
  
  // MARK: - Mouse / Trackpad event
  
  override func keyDown(_ event: NSEvent) {
    playerController.togglePause(nil)
  }
  
  /** record mouse pos on mouse down */
  override func mouseDown(_ event: NSEvent) {
    if controlBar.isDragging {
      return
    }
    mousePosRelatedToWindow = NSEvent.mouseLocation()
    mousePosRelatedToWindow!.x -= window!.frame.origin.x
    mousePosRelatedToWindow!.y -= window!.frame.origin.y
  }
  
  /** move window while dragging */
  override func mouseDragged(_ event: NSEvent) {
    if controlBar.isDragging {
      return
    }
    if mousePosRelatedToWindow != nil {
      let currentLocation = NSEvent.mouseLocation()
      let newOrigin = CGPoint(
        x: currentLocation.x - mousePosRelatedToWindow!.x,
        y: currentLocation.y - mousePosRelatedToWindow!.y
      )
      window?.setFrameOrigin(newOrigin)
    }
  }
  
  /** if don't do so, window will jitter when dragging in titlebar */
  override func mouseUp(_ event: NSEvent) {
    mousePosRelatedToWindow = nil
  }
  
  override func mouseEntered(_ event: NSEvent) {
    showUI()
  }
  
  override func mouseExited(_ event: NSEvent) {
    if controlBar.isDragging {
      return
    }
    hideUI()
  }
  
  override func mouseMoved(_ event: NSEvent) {
    if animationState == .hidden {
      showUI()
    }
    // if timer exist, destroy first
    if hideControlTimer != nil {
      hideControlTimer!.invalidate()
      hideControlTimer = nil
    }
    // create new timer
    let timeout = ud.float(forKey: Preference.Key.controlBarAutoHideTimeout)
    hideControlTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideUIAndCurdor), userInfo: nil, repeats: false)
  }
  
  
  override func scrollWheel(_ event: NSEvent) {
    if event.phase.contains(.began) {
      if event.scrollingDeltaX != 0 {
        scrollDirection = .horizontal
      } else if event.scrollingDeltaY != 0 {
        scrollDirection = .vertical
      }
    } else if event.phase.contains(.ended) {
      scrollDirection = nil
    }
    // handle the value
    let seekFactor = 0.05
    if scrollDirection == .horizontal {
      playerController.seek(relativeSecond: seekFactor * Double(event.scrollingDeltaX))
    } else if scrollDirection == .vertical {
      let newVolume = playerController.info.volume - Int(event.scrollingDeltaY)
      playerController.setVolume(newVolume)
      volumeSlider.integerValue = newVolume
      displayOSD(OSDMessage.volume(playerController.info.volume))
    }
  }
  
  // MARK: - Window delegate
  
  func windowWillEnterFullScreen(_ notification: Notification) {
    // show titlebar
    window!.titlebarAppearsTransparent = false
    window!.titleVisibility = .visible
    // remove buttons from fade-able views
    withStandardButtons { button in
      if let index = (self.fadeableViews.index {$0 === button}) {
        self.fadeableViews.remove(at: index)
      }
    }
    // remove titlebar view from fade-able views
    if let index = (self.fadeableViews.index {$0 === titleBarView}) {
      self.fadeableViews.remove(at: index)
    }
    // stop animation and hide titleBarView
    animationState = .hidden
    titleBarView.isHidden = true
    Swift.print("fullscreen")
    isInFullScreen = true
  }
  
  func windowWillExitFullScreen(_ notification: Notification) {
    // hide titlebar
    window!.titlebarAppearsTransparent = true
    window!.titleVisibility = .hidden
    // show titleBarView
    titleBarView.isHidden = false
    animationState = .shown
    // add back buttons to fade-able views
    withStandardButtons { button in
      self.fadeableViews.append(button)
    }
    // add back titlebar view to fade-able views
    self.fadeableViews.append(titleBarView)
    Swift.print("exit fullscreen")
    isInFullScreen = false
    // set back frame of videoview
    videoView.frame = window!.contentView!.frame
  }
  
  // MARK: - Control UI
  
  func hideUIAndCurdor() {
    // don't hide UI when dragging control bar
    if controlBar.isDragging {
      return
    }
    hideUI()
    NSCursor.setHiddenUntilMouseMoves(true)
  }
  
  private func hideUI() {
    fadeableViews.forEach { (v) in
      v?.alphaValue = 1
    }
    animationState = .willHide
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = 0.5
      fadeableViews.forEach { (v) in
        v?.animator().alphaValue = 0
      }
    }) {
      // if no interrupt then hide animation
      if self.animationState == .willHide {
        self.fadeableViews.forEach { (v) in
          v?.isHidden = true
        }
        self.animationState = .hidden
      }
    }
  }
  
  private func showUI () {
    animationState = .willShow
    fadeableViews.forEach { (v) in
      v?.isHidden = false
      v?.alphaValue = 0
    }
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = 0.5
      fadeableViews.forEach { (v) in
        v?.animator().alphaValue = 1
      }
    }) {
      self.animationState = .shown
    }
  }
  
  func updateTitle() {
    if let w = window, url = playerController.info.currentURL?.lastPathComponent {
      w.title = url
      titleBarTitleCell.title = url
    }
  }
  
  func displayOSD(_ message: String) {
    if hideOSDTimer != nil {
      hideOSDTimer!.invalidate()
      hideOSDTimer = nil
    }
    osdAnimationState = .shown
    osd.stringValue = message
    osd.alphaValue = 1
    osd.isHidden = false
    let timeout = ud.integer(forKey: Preference.Key.osdAutoHideTimeout)
    hideOSDTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideOSD), userInfo: nil, repeats: false)
  }
  
  @objc private func hideOSD() {
    NSAnimationContext.runAnimationGroup({ (context) in
      self.osdAnimationState = .willHide
      context.duration = 0.5
      osd.animator().alphaValue = 0
    }) {
      if self.osdAnimationState == .willHide {
        self.osdAnimationState = .hidden
      }
    }
  }
  
  // MARK: - Window size
  
  func windowDidResize(_ notification: Notification) {
    guard let w = window else { return }
    w.setFrame(w.constrainFrameRect(w.frame, to: w.screen), display: false)
    let wSize = w.frame.size, cSize = controlBar.frame.size
    // update videoview size if in full screen, since aspect ratio may changed
    if (isInFullScreen) {
      let aspectRatio = w.aspectRatio.width / w.aspectRatio.height
      let tryHeight = wSize.width / aspectRatio
      Swift.print(wSize, aspectRatio, tryHeight)
      if tryHeight < wSize.height {
        // should have black above and below
        let targetHeight = wSize.width / aspectRatio
        let yOffset = (wSize.height - targetHeight) / 2
        videoView.frame = NSMakeRect(0, yOffset, wSize.width, targetHeight)
      } else if tryHeight > wSize.height{
        // should have black left and right
        let targetWidth = wSize.height * aspectRatio
        let xOffset = (wSize.width - targetWidth) / 2
        videoView.frame = NSMakeRect(xOffset, 0, targetWidth, wSize.height)
      }
    }
    // update control bar position
    let cph = ud.float(forKey: Preference.Key.controlBarPositionHorizontal)
    let cpv = ud.float(forKey: Preference.Key.controlBarPositionVertical)
    controlBar.setFrameOrigin(NSMakePoint(
      wSize.width * CGFloat(cph) - cSize.width * 0.5,
      wSize.height * CGFloat(cpv)
    ))
  }
  
  
  /** Set video size when info available. */
  func adjustFrameByVideoSize() {
    guard let width = playerController.info.videoWidth, let height = playerController.info.videoHeight else {
      Utility.fatal("video info not available")
      return
    }
    // set aspect ratio
    let aspectRatio = Float(width) / Float(height)
    var videoSize = NSSize(width: width, height: height)
    self.window!.aspectRatio = videoSize
    // check screen size
    let screenSizeOptional = NSScreen.main()?.visibleFrame.size
    if let screenSize = screenSizeOptional {
      // check if video size > screen size
      let tryWidth = CGFloat(Float(screenSize.height) * aspectRatio)
      let tryHeight = CGFloat(Float(screenSize.width) / aspectRatio)
      if screenSize.width >= videoSize.width {
        if screenSize.height < videoSize.height {
          videoSize.height = screenSize.height
          videoSize.width = tryWidth
        }
      } else {
        // screenSize.width < videoSize.width
        if screenSize.height < videoSize.height {
          if (screenSize.height >= tryHeight) {
            videoSize.width = screenSize.width
            videoSize.height = tryHeight
          } else {
            videoSize.height = screenSize.height
            videoSize.width = tryWidth
          }
        } else {
          videoSize.width = screenSize.width
          videoSize.height = tryHeight
        }
      }
      // check default window position
    }
    
    self.window!.setContentSize(videoSize)
    if self.videoView.videoSize == nil {
      self.videoView.videoSize = videoSize
    }
    window!.setIsVisible(true)
    // UI and slider
    updatePlayTime(withDuration: true, andProgressBar: true)
    updateVolume()
    
  }
  
  // MARK: - Sync UI
  
  func updatePlayTime(withDuration: Bool, andProgressBar: Bool) {
    guard let duration = playerController.info.videoDuration, let pos = playerController.info.videoPosition else {
      Utility.fatal("video info not available")
      return
    }
    let percantage = (Double(pos.second) / Double(duration.second)) * 100
    leftLabel.stringValue = pos.stringRepresentation
    if withDuration {
      rightLabel.stringValue = duration.stringRepresentation
    }
    if andProgressBar {
      playSlider.doubleValue = percantage
    }
  }
  
  func updateVolume() {
    let volume = ud.integer(forKey: Preference.Key.softVolume)
    playerController.setVolume(volume)
    volumeSlider.integerValue = volume
  }
  
  func updatePlayButtonState(_ state: Int) {
    playButton.state = state
    if state == NSOffState {
      speedValueIndex = 5
      leftArrowLabel.isHidden = true
      rightArrowLabel.isHidden = true
    }
  }
  
  // MARK: - IBAction
  
  /** Play button: pause & resume */
  @IBAction func playButtonAction(_ sender: NSButton) {
    if sender.state == NSOnState {
      playerController.togglePause(false)
    }
    if sender.state == NSOffState {
      playerController.togglePause(true)
      // speed is already reset by playerController
      speedValueIndex = 5
      leftArrowLabel.isHidden = true
      rightArrowLabel.isHidden = true
    }
  }
  
  /** mute button */
  @IBAction func muteButtonAction(_ sender: NSButton) {
    if sender.state == NSOnState {
      playerController.toogleMute(true)
      displayOSD(OSDMessage.mute)
    }
    if sender.state == NSOffState {
      playerController.toogleMute(false)
      displayOSD(OSDMessage.unMute)
    }
  }
  
  /** left btn */
  @IBAction func leftButtonAction(_ sender: NSButton) {
    arrowButtonAction(left: true)
  }
  
  @IBAction func rightButtonAction(_ sender: NSButton) {
    arrowButtonAction(left: false)
  }
  
  /** handle action of both left and right arrow button */
  private func arrowButtonAction(left: Bool) {
    let actionType = Preference.ArrowButtonAction(rawValue: ud.integer(forKey: Preference.Key.arrowButtonAction))
    switch actionType! {
    case .speed:
      if left {
        if speedValueIndex >= 5 {
          speedValueIndex = 4
        } else if speedValueIndex <= 0 {
          speedValueIndex = 0
        } else {
          speedValueIndex -= 1
        }
      } else {
        if speedValueIndex <= 5 {
          speedValueIndex = 6
        } else if speedValueIndex >= 10 {
          speedValueIndex = 10
        } else {
          speedValueIndex += 1
        }
      }
      let speedValue = AppData.availableSpeedValues[speedValueIndex]
      playerController.setSpeed(speedValue)
      if speedValueIndex == 5 {
        leftArrowLabel.isHidden = true
        rightArrowLabel.isHidden = true
      } else if speedValueIndex < 5 {
        leftArrowLabel.isHidden = false
        rightArrowLabel.isHidden = true
        leftArrowLabel.stringValue = String(format: "%.0fx", speedValue)
      } else if speedValueIndex > 5 {
        leftArrowLabel.isHidden = true
        rightArrowLabel.isHidden = false
        rightArrowLabel.stringValue = String(format: "%.0fx", speedValue)
      }
      displayOSD(OSDMessage.speed(speedValue))
      // if is paused
      if playButton.state == NSOffState {
        updatePlayButtonState(NSOnState)
        playerController.togglePause(false)
      }
    case .playlist:
      break
    case .seek:
      playerController.seek(relativeSecond: left ? -10 : 10)
      break
    }
  }
  
  @IBAction func settingsButtonAction(_ sender: NSButton) {
    quickSettingPanel.showWindow(self)
  }
  
  
  /** When slider changes */
  @IBAction func playSliderChanges(_ sender: NSSlider) {
    let percentage = 100 * sender.doubleValue / sender.maxValue
    playerController.seek(percent: percentage)
  }
  
  
  @IBAction func volumeSliderChanges(_ sender: NSSlider) {
    let value = sender.integerValue
    playerController.setVolume(value)
    displayOSD(OSDMessage.volume(value))
  }
  
  
  // MARK: - Utilility
  
  private func withStandardButtons(_ block: (NSButton?) -> Void) {
    guard let w = window else { return }
    block(w.standardWindowButton(.closeButton))
    block(w.standardWindowButton(.miniaturizeButton))
    block(w.standardWindowButton(.zoomButton))
  }
  
}
