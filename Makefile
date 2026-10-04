.PHONY: build test check cross
build:
	mkdir -p bin
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o bin/codex-relay ./cmd/codex-relay
test:
	go test ./...
check:
	test -z "$$(gofmt -l cmd internal web)"
	go vet ./...
	go test -race ./...
cross:
	mkdir -p dist
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o dist/codex-relay-linux-amd64 ./cmd/codex-relay
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o dist/codex-relay-linux-arm64 ./cmd/codex-relay
	CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o dist/codex-relay-darwin-arm64 ./cmd/codex-relay
