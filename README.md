# Open the included Xcode project

Unzip the entire folder. On an Apple-silicon Mac with Xcode 16 or newer and a visionOS SDK, run `bash Prepare.command` to fetch and verify the detector. Open `TableLens.xcodeproj`, select the TableLens scheme, choose your signing team and device, then press Run. The five-slide PowerPoint and timed presenter notes are in Presentation/TableLens-Pitch.pptx, also visible in the project navigator.

# TableLens for Apple Vision Pro
Send this ZIP to your Mac developer. The native app analyses images on the headset using Apple Vision and a bundled Core ML object detector. It requires no robot, webcam, Python service or network connection after installation. The model recognises a fixed vocabulary of common objects; it does not identify every item or brand.

## Pick a build
- Live everyday-object scan: Apple’s restricted main-camera path. Obtain Apple's Main Camera Access entitlement for your team and app ID, and the enterprise license required for your provisioning arrangement. Place Apple's supplied license in Resources/ under its supplied filename before building. Follow Apple's instructions if your approval specifies different packaging. Open the mixed immersive space with “Scan through headset” and grant camera permission. The app periodically processes a left-camera frame and displays the captured view, names, counts and image-space boxes in its window. Those boxes are labels on the captured image; they do not remain attached to the physical objects.
- Standard AR: supply one or more trained .referenceobject files in Resources/ before building. Train them in Create ML using Apple's reference-object workflow, using a 3D model of each specific item. Name the references meaningfully. Select “Track reference objects” and allow world sensing. ARKit uses system sensing to identify enrolled objects; the app places a spatial name tag at each tracked anchor. There are no reference objects supplied because they must match your physical items.
- Standard photo scan: take a system photo on Vision Pro or import a table photo into Photos. Select “Identify from photo.” This runs the general detector on-device and is the quickest installation check without special camera access.

## Mac installation
1. Use an Apple-silicon Mac with full Xcode, a visionOS SDK supporting visionOS 2 or later, your signed-in Apple development account and Xcode 16 or newer. Pair the physical headset in Xcode, enable Developer Mode, and ensure it runs visionOS 2 or later.
2. Unzip and open Terminal inside TableLens/. For standard photo/reference modes, run `bash Install.command standard`. For the approved live-camera mode, run `bash Install.command live`. Provide your team ID and paired device identifier when prompted. Live mode additionally prompts for the entitled bundle identifier.
3. The script downloads Apple’s pretrained YOLOv3 Core ML model (roughly 62 MB), verifies its pinned SHA-256, uses the included Xcode project, and asks Xcode to build, sign, install and launch. No credentials or license are included. If provisioning fails, inspect Signing & Capabilities for the approved team/app ID and register the headset through Xcode.
4. For simulator photo testing run `bash Prepare.command`, open TableLens.xcodeproj, select a visionOS simulator and run. Physical sensing and signing require the device test.

## First acceptance test
Use a cup, book and phone under good lighting. Try a still photo first, record how many real objects the model finds, and check label and box placement. In the live build move an object, look away and return. Verify that results update, correct image orientation on your hardware, Stop releases the session, and re-entry works. In reference mode test one trained item and one untrained look-alike. This package was checked structurally on Linux. Xcode compilation, optical alignment, effective scan rate and headset installation are pending.

Apple's main-camera sample: https://developer.apple.com/documentation/visionos/accessing-the-main-camera
Enterprise capabilities: https://developer.apple.com/documentation/visionos/building-spatial-experiences-for-business-apps-with-enterprise-apis
Reference tracking: https://developer.apple.com/documentation/visionos/exploring-object-tracking-with-arkit
Model and terms: https://huggingface.co/apple/coreml-YOLOv3

## Compare a tabletop before and after
Open **Compare before & after**. Choose the baseline photo, then a second photo taken from the same height and angle. Both use Apple's pinned YOLOv3Int8LUT Core ML detector and the same 0.45 label threshold. Select a category to isolate its boxes in both images. Choose a retaken after photo to rerun the comparison while keeping the baseline. Replacing the baseline starts a new pair. Use current scan freezes the most recent displayed frame and its corresponding detections. The most recent pair is saved locally until replaced or cleared. A missing detection may reflect occlusion, framing, or model error.

For a device check, photograph two cups, a phone and a book, remove one cup, and capture the second photo. Verify the count change if the detector finds all items. Repeat using the identical photo twice (all deltas zero), then close and reopen the comparison to check persistence. Test replacing the after photo and clearing both images.

## Identify → Find → Pack up
Use Identify from photo (standard build) or Scan through headset (entitled live build). Every successful scan also feeds Find & pack up. Choose an item or search its category, e.g. phone. The latest reliable sighting shows the full scene, highlighted candidates and scan time. Successive photos simulate changing views. Live sightings require the category in two consecutive processed frames within three seconds. An old or interrupted feed expires. This is category-level evidence; multiple matches remain separate highlighted candidates. Packed is a reversible manual status. A checklist entry may also be used for a manual-only item outside the detector vocabulary.

Start with phone, mouse and book or use Start empty session and add your own items. Sightings and checklist stay in memory for this run and are cleared on restart. Earlier before/after comparison snapshots have their own separate local storage. Test an absent item, an occluded mouse, two phones, manual pack/undo, a stopped feed, and a session reset. A photo's scan time is when it was analysed, not when it was taken.
