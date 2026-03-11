#!/bin/bash
# ============================================================================
# Setup audio clips directory for Heart Rate Recorder
#
# Creates the folder structure at ~/HeartRateRecorder/clips/
# Drop your .mp3, .wav, or .m4a audio files into the appropriate folders.
# ============================================================================

CLIPS_DIR="$HOME/HeartRateRecorder/clips"

echo "Creating audio clips directory structure..."
echo ""

folders=("warmup" "easy" "moderate" "hard" "max" "start" "stop" "zone_change")

for folder in "${folders[@]}"; do
    mkdir -p "$CLIPS_DIR/$folder"
    echo "  Created: $CLIPS_DIR/$folder"
done

echo ""
echo "Directory structure created at: $CLIPS_DIR"
echo ""
echo "Folder guide:"
echo "  warmup/      — Clips for HR < 60% of max (gentle motivation)"
echo "  easy/        — Clips for HR 60-70% (encouragement)"
echo "  moderate/    — Clips for HR 70-80% (push harder)"
echo "  hard/        — Clips for HR 80-90% (intense motivation)"
echo "  max/         — Clips for HR > 90% (peak intensity)"
echo "  start/       — Played when you press Record"
echo "  stop/        — Played when you press Stop"
echo "  zone_change/ — Played when you transition between HR zones"
echo ""
echo "Supported formats: .mp3, .wav, .m4a, .aac, .aiff, .caf"
echo ""
echo "Put any number of files in each folder — one will be picked at random."
echo "If a folder is empty, the app falls back to text-to-speech."
echo ""
echo "Ideas for Arnold clips:"
echo "  • Record yourself doing impressions"
echo "  • Get a personalized Cameo from Arnold himself"
echo "  • Use a licensed soundboard app to save individual clips"
echo "  • Use an AI voice tool (ElevenLabs, etc.) to generate custom lines"
