import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    self.contentViewController = flutterViewController

    // Keep the app above the 840pt-wide breakpoint that switches the tool
    // view to its "mobile" layout — that layout builds and keeps alive
    // every auto-launched module's full subtree at once (including nested
    // sub-apps and real WebViews) instead of just the active one, which is
    // fine on an actual narrow/mobile screen but not on a desktop window
    // that simply starts small.
    let minContentSize = NSSize(width: 900, height: 650)
    self.contentMinSize = minContentSize
    windowFrame.size.width = max(windowFrame.size.width, minContentSize.width)
    windowFrame.size.height = max(windowFrame.size.height, minContentSize.height)
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
