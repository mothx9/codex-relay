package codex

import (
	"encoding/json"
	"github.com/mothx9/codex-relay/internal/protocol"
	"strings"
	"testing"
)

func TestImageInputAdapterAndHistoryMetadata(t *testing.T) {
	for _, kind := range []string{protocol.NewTurn, protocol.FollowUpCommand, protocol.Steer} {
		input := messageInput(protocol.Command{Kind: kind, Text: "inspect", Images: []protocol.ImageInput{{MediaType: "image/png", Data: "IMAGE_BYTES"}}})
		if len(input) != 2 || input[1]["type"] != "image" || input[1]["url"] != "data:image/png;base64,IMAGE_BYTES" {
			t.Fatal(input)
		}
	}
	item := activity(json.RawMessage(`{"id":"image-item","clientId":"client","type":"userMessage","content":[{"type":"image","url":"data:image/png;base64,PRIVATE_BYTES"}]}`))
	if item.ImageCount != 1 || item.ClientID != "client" {
		t.Fatal("image-only user identity lost", item)
	}
	wire, _ := json.Marshal(item)
	if strings.Contains(string(wire), "PRIVATE_BYTES") {
		t.Fatal("image bytes entered Relay history")
	}
}
