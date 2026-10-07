package protocol

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"image"
	"image/png"
	"strings"
	"testing"
)

func TestInlineImagesAreBoundedAndCannotReferenceRemoteFiles(t *testing.T) {
	var b bytes.Buffer
	if err := png.Encode(&b, image.NewRGBA(image.Rect(0, 0, 8, 8))); err != nil {
		t.Fatal(err)
	}
	valid := ImageInput{MediaType: "image/png", Data: base64.StdEncoding.EncodeToString(b.Bytes())}
	if err := ValidateImages([]ImageInput{valid, valid}); err != nil {
		t.Fatal(err)
	}
	for _, bad := range [][]ImageInput{{valid, valid, valid}, {{MediaType: "image/jpeg", Data: valid.Data}}, {{MediaType: "image/png", Data: "https://private.invalid/image.png"}}, {{MediaType: "image/png", Data: "/etc/passwd"}}, {{MediaType: "image/png", Data: strings.Repeat("A", base64.StdEncoding.EncodedLen(MaxImageBytes)+1)}}} {
		if ValidateImages(bad) == nil {
			t.Fatal("invalid input accepted")
		}
	}
	encoded, _ := json.Marshal(Message{Type: "command", Command: &Command{ID: ID(), Kind: NewTurn, Images: []ImageInput{{MediaType: "image/jpeg", Data: strings.Repeat("A", base64.StdEncoding.EncodedLen(MaxImageBytes))}, {MediaType: "image/jpeg", Data: strings.Repeat("A", base64.StdEncoding.EncodedLen(MaxImageBytes))}}, Text: strings.Repeat("t", MaxText)}})
	if len(encoded) >= MaxMessage {
		t.Fatal("image budget exceeds existing transport bound", len(encoded))
	}
	session := Session{Status: Ready, Capabilities: Capabilities{CanSend: true}}
	if CheckControl(session, Command{Kind: NewTurn, Images: []ImageInput{valid}}) != CodexRejected {
		t.Fatal("older Agent accepted image capability")
	}
	session.Capabilities.CanSendImages = true
	if CheckControl(session, Command{Kind: NewTurn, Images: []ImageInput{valid}}) != "" {
		t.Fatal("image input unavailable")
	}
}
