build:
	swift build


test:
	swift test


format:
	swift-format -i ./Sources ./Tests --recursive --parallel
