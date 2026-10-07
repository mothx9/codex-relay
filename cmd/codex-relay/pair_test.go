package main

import (
	"context"
	"strings"
	"testing"
)

func TestPairingCodeInputIsBoundedAndNeverAcceptsReusableCredentials(t *testing.T) {
	for _, raw := range []string{"12345678", "1234 5678\n", " 12345678 \n"} {
		got, err := readPairingCode(strings.NewReader(raw))
		if err != nil || got != "12345678" {
			t.Fatal(got, err)
		}
	}
	for _, raw := range []string{"", "123", strings.Repeat("a", 64), "abcdefgh", "１２３４５６７８", strings.Repeat("1", 10000)} {
		if _, err := readPairingCode(strings.NewReader(raw)); err == nil {
			t.Fatal("accepted invalid credential input")
		}
	}
}
func TestPairingRejectsConflictingCodeSourcesBeforeNetwork(t *testing.T) {
	err := pairingCommand(context.Background(), []string{"--code", "12345678", "--code-stdin"})
	if err == nil || !strings.Contains(err.Error(), "choose only one") {
		t.Fatal(err)
	}
}
