// MARK: Cordova Exposures.

import AVFoundation
import CoreImage
import MediaPlayer
import UIKit
import CameraManager
import AVKit;

let cameraManager = CameraManager()
var parentView: UIView? = nil;
var previewView: UIView? = nil;
var view = UIView(frame: parentView!.bounds);

var cameraStarted: Bool = false;
var windowRect = CGRect()
var deviceWidth = 0;
var deviceHeight = 0;

extension UIImage {

    func save(at directory: FileManager.SearchPathDirectory,
              pathAndImageName: String,
              createSubdirectoriesIfNeed: Bool = true,
              compressionQuality: CGFloat = 1.0)  -> URL? {
        do {
        let documentsDirectory = try FileManager.default.url(for: directory, in: .userDomainMask,
                                                             appropriateFor: nil,
                                                             create: false)
        return save(at: documentsDirectory.appendingPathComponent(pathAndImageName),
                    createSubdirectoriesIfNeed: createSubdirectoriesIfNeed,
                    compressionQuality: compressionQuality)
        } catch {
            print("-- Error: \(error)")
            return nil
        }
    }

    func save(at url: URL,
              createSubdirectoriesIfNeed: Bool = true,
              compressionQuality: CGFloat = 1.0)  -> URL? {
        do {
            if createSubdirectoriesIfNeed {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
            }
            guard let data = jpegData(compressionQuality: compressionQuality) else { return nil }
            try data.write(to: url)
            return url
        } catch {
            print("-- Error: \(error)")
            return nil
        }
    }
}

// MARK: BIG PICTURE FUNCTIONS
@objc(LastCam) class LastCam: CDVPlugin {
    @objc(startCamera:)
    func startCamera(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult (status: CDVCommandStatus_ERROR);

        // stop the device from being able to sleep
        UIApplication.shared.isIdleTimerDisabled = true

        // Command Arguments
        let x:Int = command.arguments![0] as! Int;
        let y:Int = command.arguments![1] as! Int;
        let width:Int = command.arguments![2] as! Int;
        let height:Int = command.arguments![3] as! Int;
        deviceWidth = width;
        deviceHeight = height;

        // get rid of the old view (causes issues if the app is resumed)
        parentView = nil;

        //make the view
        let viewRect = CGRect.init(x: x, y: y, width: width, height: height)
        windowRect = CGRect.init(x: x, y: y, width: width, height: height)

        parentView = UIView(frame: viewRect)
        webView?.superview?.addSubview(parentView!)
        parentView!.addSubview(view)
        parentView!.isUserInteractionEnabled = true

        // This is needed so that we can show the camera buttons above the camera-view.
        webView?.isOpaque = false
        webView?.backgroundColor = UIColor.clear

        cameraManager.cameraOutputMode = CameraOutputMode.stillImage;
        cameraManager.writeFilesToPhoneLibrary = false
        cameraManager.imageAlbumName =  "uSync Images"
        cameraManager.videoAlbumName =  "uSync Videos"

        cameraManager.addPreviewLayerToView(parentView!)

        // Add this in there, incase the camera session has already been created.
        cameraManager.resumeCaptureSession();

        webView.superview?.bringSubviewToFront(webView);

        cameraStarted = true;

        pluginResult = CDVPluginResult(status: CDVCommandStatus_OK);
        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
    }

    @objc(stopCamera:)
    func stopCamera(command: CDVInvokedUrlCommand) {

        cameraManager.stopCaptureSession();

        // Remove the view, so that we don't see the last frame of the stream.
        parentView?.removeFromSuperview();
        parentView = nil;

        cameraStarted = false;

        var pluginResult = CDVPluginResult (status: CDVCommandStatus_ERROR);
        pluginResult = CDVPluginResult(status: CDVCommandStatus_OK);

        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
    }

    @objc(takePicture:)
    func takePicture(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Camera session isn't started");
        if(!cameraStarted) {
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        } else {
            cameraManager.capturePictureWithCompletion({ result in
                switch result {
                    case .failure:
                        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
                        // error handling
                    case .success(let content):
                        let path = "photo/temp/img_" + String(Date().timeIntervalSince1970) + ".jpg";
                        let image = content.asImage;
                        // Save Image
                        guard let imgPath = image?.save(at: .documentDirectory, pathAndImageName: path) else { return }
                        
                        // Inform JS of image capture
                        pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: imgPath.absoluteString);
                        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
                        
                        // Show Preview of Image Captured
                        previewView = UIImageView(image:image);
                        previewView!.frame = windowRect;
                        previewView!.backgroundColor = UIColor.darkGray;
                        previewView!.contentMode = UIView.ContentMode.scaleAspectFit;
                        self.webView?.superview?.addSubview(previewView!)
                        self.webView.superview?.bringSubviewToFront(self.webView);
                }
            });
        }
    }
    
    @objc(closePreview:)
    func closePreview(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Camera session isn't started");
        if(!cameraStarted) {
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        } else {
            previewView?.removeFromSuperview();
            previewView = nil;
            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "Preview Closed.");
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        }
    }

    @objc(switchCamera:)
    func switchCamera(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Camera session isn't started");

        if(!cameraStarted) {
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        } else {
            let cameraDevice = cameraManager.cameraDevice;
            let cameraView = cameraDevice == CameraDevice.front ? "back" : "front"

            cameraManager.cameraDevice = cameraDevice == CameraDevice.front ? CameraDevice.back : CameraDevice.front

            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: cameraView);
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        }
    }

    @objc(switchFlash:)
    func switchFlash(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Camera session isn't started");
        if(!cameraStarted) {
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        } else {
            cameraManager.changeFlashMode();
            let flashMode = cameraManager.flashMode;

            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: flashMode.rawValue);
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        }
    }

    @objc(startVideoCapture:)
    func startVideoCapture(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Camera session isn't started");
        if(!cameraStarted) {
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        } else {

            if(cameraManager.cameraOutputMode == .stillImage) {
                print("Camera output is stillImage, switching to videoWithMic");
                cameraManager.cameraOutputMode = CameraOutputMode.videoWithMic;
            }

            cameraManager.startRecordingVideo();
            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK);
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        }
    }

    @objc(stopVideoCapture:)
    func stopVideoCapture(command: CDVInvokedUrlCommand) {

        var pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Camera session isn't started");
        if(!cameraStarted) {
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        } else {

            cameraManager.stopVideoRecording { (Url, error) in

                let asset = AVURLAsset(url: NSURL(fileURLWithPath: (Url?.absoluteString)!) as URL, options: nil)
                let imgGenerator = AVAssetImageGenerator(asset: asset)
                let cgImage = try? imgGenerator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil);
                // !! check the error before proceeding
                let uiImage = UIImage(cgImage: cgImage!)
                let base64Image = uiImage.jpegData(compressionQuality: 0.85)!
                    .base64EncodedString(options: .lineLength64Characters)

                let returnValues = [Url?.absoluteString, base64Image];

                pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: returnValues as [Any]);
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
                if(cameraManager.cameraOutputMode == .videoWithMic) {
                    cameraManager.cameraOutputMode = CameraOutputMode.stillImage;
                }
                let player = AVPlayer(url: URL(string: Url!.absoluteString)!);
                let playerController = AVPlayerLayer(player: player);
                
                let previewView = UIView();
                previewView.frame = windowRect;
                playerController.frame = windowRect;
                previewView.backgroundColor = UIColor.black;
                previewView.layer.addSublayer(playerController);
                
                self.webView?.superview?.addSubview(previewView);
                self.webView.superview?.bringSubviewToFront(self.webView);
                
                player.play();
            }
        }

    }

    @objc(recordingTimer:)
    func recordingTimer(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Camera session isn't started");
        if(!cameraStarted) {
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        } else {
            let duration = cameraManager.recordedDuration.seconds;
            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: duration);
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId);
        }
    }


}
