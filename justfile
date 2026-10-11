dev_app := "build/debug/Tangent.app"

# List recipes
default:
    @just --list

# Debug build for this Mac's architecture, wrapped in an .app bundle
build:
    swift build
    rm -rf {{dev_app}}
    mkdir -p {{dev_app}}/Contents/MacOS
    cp "$(swift build --show-bin-path)/Tangent" {{dev_app}}/Contents/MacOS/Tangent
    cp Resources/Info.plist {{dev_app}}/Contents/Info.plist
    codesign --force --sign - {{dev_app}}

# Build and run in the foreground with logs in the terminal (Ctrl-C quits)
run: build
    -pkill -x Tangent
    {{dev_app}}/Contents/MacOS/Tangent

# Universal release build into build/Tangent.app
release:
    ./build.sh

# Release build, install to /Applications and launch
install:
    ./build.sh install

# Remove build output
clean:
    swift package clean
    rm -rf build
