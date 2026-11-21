# TableLens

**Find an everyday item by seeing where it last appeared, then check it off when you pack it.** TableLens is an Apple Vision Pro prototype for people clearing a shared workspace after a class, hackathon or workshop.

Imagine packing up a laptop and losing sight of the mouse. Search for **mouse** in TableLens to see the latest scan that recognised one, with its location highlighted. The surrounding objects in the image can help you decide where to look. Once you have the mouse in your bag, select **Mark packed**.

[Download the project pitch](Presentation/TableLens-Pitch.pptx)

## Try the core workflow

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

## License

The repository includes [CC0 1.0 Universal](LICENSE). The pretrained detector is distributed separately by Apple. See the [model card and terms](https://huggingface.co/apple/coreml-YOLOv3).
