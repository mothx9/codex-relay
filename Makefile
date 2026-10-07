VERSION ?= 0.1.0-rc.5
LDFLAGS = -s -w -X main.version=$(VERSION)

.PHONY: build test check cross checksums
build:
	mkdir -p bin
	CGO_ENABLED=0 go build -trimpath -ldflags="$(LDFLAGS)" -o bin/codex-relay ./cmd/codex-relay
test:
	go test ./...
	node web/control.test.mjs
	python3 scripts/install_test.py
check:
	test -z "$$(gofmt -l cmd internal web)"
	go vet ./...
	go test -race ./...
	node web/control.test.mjs
	python3 scripts/install_test.py
	python3 scripts/localization.py --check
cross:
	mkdir -p dist
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="$(LDFLAGS)" -o dist/codex-relay-linux-amd64 ./cmd/codex-relay
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags="$(LDFLAGS)" -o dist/codex-relay-linux-arm64 ./cmd/codex-relay
	CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags="$(LDFLAGS)" -o dist/codex-relay-darwin-arm64 ./cmd/codex-relay

checksums: cross
	python3 scripts/checksums.py
