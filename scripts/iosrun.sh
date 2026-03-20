project=$(find . -maxdepth 1 -name "*.xcodeproj" | head -1)
scheme=$(basename "$project" .xcodeproj)
derived=".derived-data"
sim_name="${1:-iPhone 16e}"

if [[ -z "$project" ]]; then
  echo "No .xcodeproj found in current directory"
  exit 1
fi

echo "Building $scheme..."
if ! xcodebuild -project "$project" -scheme "$scheme" \
  -destination "platform=iOS Simulator,name=$sim_name" \
  -derivedDataPath "$derived" build -quiet; then
  echo "Build failed"
  exit 1
fi

echo "Build succeeded. Launching simulator..."

xcrun simctl boot "$sim_name" 2>/dev/null || true
open -a Simulator

app_path="$derived/Build/Products/Debug-iphonesimulator/$scheme.app"
bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Info.plist")

echo "Installing $scheme..."
while ! xcrun simctl install "$sim_name" "$app_path" 2>/dev/null; do
  sleep 0.5
done

echo "Launching $bundle_id..."
while ! xcrun simctl launch "$sim_name" "$bundle_id" 2>&1 | grep -q "$bundle_id"; do
  sleep 0.5
done

echo "Launched $bundle_id - streaming logs (Ctrl+C to stop)"
echo "----------------------------------------"

xcrun simctl spawn "$sim_name" log stream \
  --predicate "(subsystem CONTAINS '$bundle_id' OR process == '$scheme') AND NOT subsystem BEGINSWITH 'com.apple'" \
  --style compact \
  --color always 2>/dev/null | while read -r line; do
  if [[ "$line" == *"error"* ]] || [[ "$line" == *"Error"* ]]; then
    printf '\033[31m%s\033[0m\n' "$line"
  elif [[ "$line" == *"warning"* ]] || [[ "$line" == *"Warning"* ]]; then
    printf '\033[33m%s\033[0m\n' "$line"
  else
    echo "$line"
  fi
done
