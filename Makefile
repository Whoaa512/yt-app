.PHONY: build run clean dmg

build:
	cd YTApp && xcodebuild -project YTApp.xcodeproj -scheme YTApp -configuration Debug build SYMROOT=../build

release:
	cd YTApp && xcodebuild -project YTApp.xcodeproj -scheme YTApp -configuration Release build SYMROOT=../build

run: build
	open build/Debug/YTApp.app

clean:
	rm -rf build
	cd YTApp && xcodebuild -project YTApp.xcodeproj -scheme YTApp clean 2>/dev/null || true

dmg: release
	hdiutil create -volname "YTApp" -srcfolder build/Release/YTApp.app -ov -format UDZO YTApp.dmg
