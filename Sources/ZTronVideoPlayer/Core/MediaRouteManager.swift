#if os(iOS)
  import AVFoundation
  import MediaPlayer

  /// For iOS devices, TinyVideoPlayer can detect three media routing modes:
  ///
  /// - airplayPlayback: Media is routed to an Airplay capable device. The video content is *only* rendered on
  /// this device, and video rendering on the iOS device is completely off.
  ///
  /// - airplayPlaybackMirroring: The screen of the iOS device is mirrored to the Airplay capable device.
  /// The video content is rendered on *both* devices.
  ///
  /// - routeOff: Media routing is off. Video is playing on the iOS device.
  public enum MediaRouteState {
    case airplayPlayback
    case airplayPlaybackMirroring
    case routeOff
  }

  /// This manager can be used as a standalone component in your project to observe
  /// and react to media route change events.
public final class MediaRouteManager: TinyLogging, @unchecked Sendable {

    /* The single acess point of this component. */
    public static let sharedManager = MediaRouteManager()

    /* Register as a delegate to receive MediaRouteManagerDelegate callbacks. */
    weak private var delegate: MediaRouteManagerDelegate?

    /* This closure is called whenever the route state is changed. */
    public var onStateChangeClosure: ((_ routeState: MediaRouteState) -> Void)?

    /*
        This closure is called whenever the availability of media routing is changed.
        E.g. An Airplay capable device is deteced in the local network.
     */
    public var onAvailablityChangeClosure: ((_ available: Bool) -> Void)?

    /* */
    public var mediaRouteState: MediaRouteState = .routeOff {
      didSet {
        delegate?.mediaRouteStateHasChangedTo(state: self.mediaRouteState)
      }
    }

    public var loggingLevel: TinyLoggingLevel = .info

    @MainActor lazy private var volumeView: MPVolumeView = .init(frame: .zero)

    private let delegateLock = DispatchSemaphore(value: 1)

    
    private init() {
        
      NotificationCenter.default.addObserver(
        forName: NSNotification.Name.MPVolumeViewWirelessRouteActiveDidChange,
        object: nil,
        queue: OperationQueue.main,
        using: { @Sendable [unowned self] notification in
            Task(priority: .high) { @MainActor in
                var newState: MediaRouteState = self.mediaRouteState

                if self.isAirPlayConnected {

                  if self.isAirPlayPlaybackActive {

                    newState = .airplayPlayback
                    self.verboseLog("Airplay playback activated!")

                  } else if self.isAirplayMirroringActive {

                    newState = .airplayPlaybackMirroring
                    self.verboseLog("Airplay playback mirroring activated!")
                  }

                } else {

                  newState = .routeOff
                  self.verboseLog("External playback deactivated!")
                }

                self.delegate?.mediaRouteStateHasChangedTo(state: newState)

                self.onStateChangeClosure?(newState)

            }
        })

      NotificationCenter.default.addObserver(
        forName: NSNotification.Name.MPVolumeViewWirelessRoutesAvailableDidChange,
        object: nil,
        queue: OperationQueue.main,
        using: { [unowned self] notification in
            Task(priority: .high) { @MainActor in
                self.delegate?.wirelessRouteAvailabilityChanged(
                  available: self.volumeView.areWirelessRoutesAvailable)

                self.onAvailablityChangeClosure?(self.volumeView.areWirelessRoutesAvailable)
            }
        })
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    /**
        This read-only variable tells generally wether the current media playback is routed via Airplay.
     */
    @MainActor public var isAirPlayConnected: Bool {
        get {
            let result = self.volumeView.isWirelessRouteActive
            return result
        }
    }

    /**
        This read-only variable tells wether the current media playback is routed wirelessly via mirroring mode.
     */
    @MainActor
    public var isAirplayMirroringActive: Bool {

        get {
            if isAirPlayConnected {
              let screens = UIScreen.screens
              if screens.count > 1 {
                return (screens[1].mirrored == UIScreen.main)
              }
            }

            return false

        }
    }

    /**
        This read-only variable tells wether the current video stream is routed to an Airplay capable device.
     */
    @MainActor
    public var isAirPlayPlaybackActive: Bool {
        get {
            return isAirPlayConnected && isAirplayMirroringActive
        }
    }

    /**
        This read-only variable tells wether the current video stream is routed via a HDMI cable.
     */
    public var isWiredPlaybackActive: Bool {
        get async {
            if await isAirPlayPlaybackActive {
              return false
            }

            let screens = await UIScreen.screens
            if screens.count > 1 {
              return await screens[1].mirrored == UIScreen.main
            }

            return false
          }
        }

    
    public func setDelegate(_ theDelegate: (any MediaRouteManagerDelegate)?) {
        self.delegateLock.wait()
        self.delegate = theDelegate
        self.delegateLock.signal()
    }
  }

public protocol MediaRouteManagerDelegate: AnyObject, Sendable {

    var mediaRouteManager: MediaRouteManager { get }

    /**
        This delegate method gets called whenever the media route state is changed.
        This can be a consequence of switching on/off Airplay or connect to a external display with a HDMI cable.
     */
    func mediaRouteStateHasChangedTo(state: MediaRouteState)

    /**
        This delegate methods gets called when the system detects that there is an external
        playback device (Bluetooth, Airplay) becomes available/unavailable in the local connectivity.
     */
    func wirelessRouteAvailabilityChanged(available: Bool)
  }

#endif
