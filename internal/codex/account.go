package codex

import (
	"context"
	"encoding/json"
	"github.com/mothx9/codex-relay/internal/protocol"
)

// Account reads the official minimal account view. It does not refresh or export tokens.
func (a *Adapter) Account(ctx context.Context) *protocol.Account {
	raw, err := a.rpc(ctx, "account/read", map[string]bool{"refreshToken": false})
	if err != nil {
		return nil
	}
	var view struct {
		Account *struct {
			Type  string `json:"type"`
			Email string `json:"email"`
			Plan  string `json:"planType"`
		} `json:"account"`
	}
	if json.Unmarshal(raw, &view) != nil || view.Account == nil {
		return nil
	}
	return &protocol.Account{Kind: protocol.Clip(view.Account.Type, 32), Email: protocol.Clip(view.Account.Email, 254), Plan: protocol.Clip(view.Account.Plan, 64)}
}
