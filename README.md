# TableLens

**Find an everyday item by seeing where it last appeared, then check it off when you pack it.** TableLens is a native Apple Vision Pro app and a cross-platform browser prototype for people clearing a shared workspace after a class, hackathon or workshop.

Imagine packing up a laptop and losing sight of the mouse. Search for **mouse** in TableLens to see the latest scan that recognised one, with its location highlighted. The surrounding objects in the image can help you decide where to look. Once you have the mouse in your bag, select **Mark packed**.

[Download the project pitch](Presentation/TableLens-Pitch.pptx)

## Choose your version

| | Native visionOS | Web browser |
| --- | --- | --- |
| Detector | Apple Core ML YOLOv3 | TensorFlow.js COCO-SSD |
| Input | Photo, video or approved headset camera | Photo, video or a camera exposed by the browser |
| Comparison | Inspect both images and their detected counts | Compare category counts from two saved scans |
| Storage | Session sightings in memory; comparison saved locally | Session and comparison in memory |

**Quick browser demo:** From the repository root run `python3 -m http.server 8000 --directory web` (Windows: `py -m http.server 8000 --directory web`). Open `http://localhost:8000`, choose a photo, then search for an object that was detected. On another device use an HTTPS deployment of the web folder. Detector downloads require internet access.

## Try the core workflow on Vision Pro

The quickest demo uses two desk photos and the standard build. Take one photo with a mouse beside a laptop. Take another from the same angle with the mouse hidden.

1. Choose **Identify from photo** and scan the first image. Check that the detector labels the mouse.
2. Scan the second image. Open **Find & pack up** and search for **mouse**. If the second scan missed the mouse, its earlier highlighted sighting remains available.
3. Select **Mark packed** after recovering it. You can undo this action. If two mice or phones appear, inspect the highlighted candidates to identify yours.
4. Open **Compare before & after** to compare the same two images. Select either photo first, then tap a category to highlight its detections in both views.

| Feature | What it tells you |
| --- | --- |
| Identify objects | Names and boxes for supported object categories visible in a photo or frame. |
| Find my item | The most recent qualifying sighting of a category during this session, including the image and scan time. |
| Pack-up checklist | Whether a category was seen in the latest scan, remains unconfirmed, or was marked packed by the wearer. |
| Before and after | How detected counts differ between two views. A lower count can mean an object was covered or outside the frame. |

## Run on a Mac

Use an Apple-silicon Mac with Xcode 16 or later, the visionOS SDK, and a visionOS 2 or later simulator or headset. The first setup needs internet access to download the detector.

```bash
git clone https://github.com/GauravWarke/TableLens.git
cd TableLens
bash Prepare.command
open TableLens.xcodeproj
```

Choose the **TableLens** scheme and a visionOS simulator, then press **Run**. Import a desk photo into the simulator’s Photos library to try the walkthrough. The checked-in Xcode project opens directly.

**Install on a headset.** Pair the headset with Xcode, enable Developer Mode, and sign in to your development team. Run the following from the repository root. The script prompts for your team ID and the paired headset identifier, then builds, signs, installs and launches the app.

```bash
bash Install.command standard
```

## Choose an input

| Input | Setup |
| --- | --- |
| Photo or recorded video | In the standard build, choose **Identify from photo** or **Scan video or photo**. A video lets you try changing scenes without main-camera access. |
| Live headset camera | Requires Apple-approved Main Camera Access for the team and bundle ID, the applicable license and user permission. Follow Apple’s license packaging instructions, then run `bash Install.command live` and enter the approved bundle ID. If camera capture is unavailable, use the media picker. |
| Trained reference object | For a spatial label attached to a specific physical item, add its trained `.referenceobject` file to `Resources/`, rebuild, and choose **Track reference objects**. Everyday photo recognition uses the bundled detector instead. |

[Apple main-camera setup](https://developer.apple.com/documentation/visionos/accessing-the-main-camera) · [ARKit reference-object tracking](https://developer.apple.com/documentation/visionos/exploring-object-tracking-with-arkit)

## How it works

SwiftUI presents the scans and checklist. Apple Vision runs **Apple’s Core ML YOLOv3** detector on-device. The setup script downloads a pinned model revision and verifies its SHA-256 checksum. The app keeps predictions with a top label score of at least 0.45 and excludes the dining-table category so the surface itself doesn’t clutter the inventory.

For the live headset feed, a category must appear in two consecutive processed frames within three seconds to update its sighting. If a subsequent scan loses it, the saved image remains useful. Only an explicit user action marks an item packed. The timestamp records when TableLens analysed the image.

**Data lifetime:** The checklist and last sightings are held in memory for the current app run. The most recent before-and-after pair is saved locally and can be cleared in the comparison screen.

**Scope:** Recognition is category-based. Similar objects may share a label, and small or hidden objects may go undetected. Photo boxes show positions in the captured image. The prototype’s speed, accuracy and effect on search time still need measurement on a physical headset.

## Code guide

| File | Responsibility |
| --- | --- |
| [TableLens.swift](App/TableLens.swift) | App entry point, detector, photo/video input, live camera and AR reference tracking |
| [PackUp.swift](App/PackUp.swift) | Last sightings, category search and manual packing checklist |
| [Comparison.swift](App/Comparison.swift) | Side-by-side photos, category counts and local comparison storage |
| [Prepare.command](Prepare.command) | Download and verify the Core ML model |
| [Install.command](Install.command) | Build, sign and install the standard or live configuration |


## Other headsets, phones and computers

Open the cross-platform browser client from `web/`. It runs the COCO-SSD MobileNet detector using TensorFlow.js on the device. Apple Core ML YOLOv3 remains the native visionOS detector. Expect differences between their predictions. The web interface supports identification, last-seen images, a manual pack-up list and before/after count comparison. All browser session data is in memory and clears on reload.

Headset browsers may display the app as a floating 2D page. Access to a passthrough camera depends on the device and its browser. A native Android XR or Quest package is outside this release.

## Verification

Run these from the repository root with Node.js 20+ and Bash:

```bash
node web/test.mjs
npx --yes eslint@9.39.5 web/*.mjs --max-warnings=0
node --check web/app.mjs && node --check web/session.mjs
bash -n Install.command && bash -n Prepare.command
```

These checks exercise session rules and parse the sources. To test recognition, load the same desk photo in both clients, check the labels, then scan a second view with an item obscured. Record false detections and inspect its last sighting. Native compilation, headset camera access and live performance must be verified on the target device.

## Licensing and models

See the [repository license](LICENSE), [Apple model card](https://huggingface.co/apple/coreml-YOLOv3) and [TensorFlow.js COCO-SSD project](https://github.com/tensorflow/tfjs-models/tree/master/coco-ssd) for the respective terms and model information.
