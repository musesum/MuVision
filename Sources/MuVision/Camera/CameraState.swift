
import AVFoundation

public enum CameraState {
    case ready      // Ready to start capturing
    case streaming  // Capture in progress
    case stopped    // Capturing stopped
    case waiting    // Waiting to get access to hardware
    // case error   // An error has occured
}
