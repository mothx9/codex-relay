package codex

import (
	"context"
	"encoding/json"
	"github.com/mothx9/codex-relay/internal/protocol"
	"time"
)

// Account reads the official minimal account view. It does not refresh or export tokens.
func (a *Adapter) Account(ctx context.Context) *protocol.Account {
	started := time.Now()
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
	account := &protocol.Account{Kind: protocol.Clip(view.Account.Type, 32), Email: protocol.Clip(view.Account.Email, 254), Plan: protocol.Clip(view.Account.Plan, 64), Source: "codex/account/read", ObservedAt: time.Now().UTC()}
	if raw, err := a.rpc(ctx, "account/rateLimits/read", map[string]any{}); err == nil {
		var limits struct {
			RateLimits *protocol.AccountLimits `json:"rateLimits"`
		}
		if json.Unmarshal(raw, &limits) == nil {
			account.Limits = limits.RateLimits
			boundLimits(account.Limits)
		}
	}
	a.mu.Lock()
	if a.account != nil && a.account.ObservedAt.After(started) {
		account = a.account
	}
	a.account = account
	a.mu.Unlock()
	return account
}

func boundLimits(l *protocol.AccountLimits) {
	if l == nil {
		return
	}
	l.LimitID = protocol.Clip(l.LimitID, 128)
	l.Plan = protocol.Clip(l.Plan, 64)
	if l.Credits != nil && l.Credits.Balance != nil {
		v := protocol.Clip(*l.Credits.Balance, 64)
		l.Credits.Balance = &v
	}
	if l.IndividualLimit != nil {
		l.IndividualLimit.Limit = protocol.Clip(l.IndividualLimit.Limit, 64)
		l.IndividualLimit.Used = protocol.Clip(l.IndividualLimit.Used, 64)
	}
}

// Sparse updates merge only supported metadata; secrets and unknown fields vanish.
func (a *Adapter) accountEvent(m rpcMessage) bool {
	if m.Method != "account/updated" && m.Method != "account/rateLimits/updated" {
		return false
	}
	var p struct {
		AuthMode *string                 `json:"authMode"`
		Plan     *string                 `json:"planType"`
		Limits   *protocol.AccountLimits `json:"rateLimits"`
	}
	if json.Unmarshal(m.Params, &p) != nil {
		return true
	}
	a.mu.Lock()
	account := protocol.Account{}
	if a.account != nil {
		account = *a.account
	}
	if m.Method == "account/updated" {
		// Identity may have changed: never carry the previous email or quota forward.
		account = protocol.Account{}
		if p.AuthMode != nil {
			account.Kind = protocol.Clip(*p.AuthMode, 32)
		}
		if p.Plan != nil {
			account.Plan = protocol.Clip(*p.Plan, 64)
		}
	} else if p.Limits != nil {
		limits := protocol.AccountLimits{}
		if account.Limits != nil {
			limits = *account.Limits
		}
		next := p.Limits
		boundLimits(next)
		if next.LimitID != "" && next.LimitID != limits.LimitID {
			limits = protocol.AccountLimits{LimitID: next.LimitID}
		}
		if next.Plan != "" {
			limits.Plan = next.Plan
			account.Plan = next.Plan
		}
		if next.Primary != nil {
			limits.Primary = next.Primary
		}
		if next.Secondary != nil {
			limits.Secondary = next.Secondary
		}
		if next.Credits != nil {
			limits.Credits = next.Credits
		}
		if next.IndividualLimit != nil {
			limits.IndividualLimit = next.IndividualLimit
		}
		limits.SpendControlReached = next.SpendControlReached
		account.Limits = &limits
	}
	account.Source = "codex/" + m.Method
	account.ObservedAt = time.Now().UTC()
	a.account = &account
	a.mu.Unlock()
	a.emit(protocol.Event{Kind: "account", Account: &account, RawEvent: m.Method})
	return true
}
