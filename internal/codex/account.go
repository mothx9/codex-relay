package codex

import (
	"context"
	"encoding/json"
	"github.com/mothx9/codex-relay/internal/protocol"
	"sort"
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
			RateLimits           *protocol.AccountLimits           `json:"rateLimits"`
			AccountID            string                            `json:"accountId"`
			Buckets              map[string]protocol.AccountLimits `json:"rateLimitsByLimitId"`
			OrdinaryUsageAllowed *bool                             `json:"ordinaryUsageAllowed"`
			ResetCredits         *protocol.ResetCredits            `json:"rateLimitResetCredits"`
		}
		if json.Unmarshal(raw, &limits) == nil {
			account.ID = protocol.Clip(limits.AccountID, 256)
			account.Buckets = boundBuckets(limits.Buckets)
			account.OrdinaryUsageAllowed = limits.OrdinaryUsageAllowed
			account.ResetCredits = limits.ResetCredits
			if account.ResetCredits != nil {
				if len(account.ResetCredits.Credits) > 100 {
					account.ResetCredits.Credits = account.ResetCredits.Credits[:100]
				}
				for i := range account.ResetCredits.Credits {
					c := &account.ResetCredits.Credits[i]
					c.ID = protocol.Clip(c.ID, 128)
					c.Status = protocol.Clip(c.Status, 64)
					c.ResetType = protocol.Clip(c.ResetType, 64)
					if c.Title != nil {
						v := protocol.Clip(*c.Title, 256)
						c.Title = &v
					}
					if c.Description != nil {
						v := protocol.Clip(*c.Description, 1024)
						c.Description = &v
					}
				}
			}
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
	a.emit(protocol.Event{Kind: "account", Account: account, RawEvent: "account/read"})
	return account
}

func boundLimits(l *protocol.AccountLimits) {
	if l == nil {
		return
	}
	l.LimitID = protocol.Clip(l.LimitID, 128)
	l.Plan = protocol.Clip(l.Plan, 64)
	l.Name = protocol.Clip(l.Name, 128)
	l.Model = protocol.Clip(l.Model, 128)
	l.ReachedType = protocol.Clip(l.ReachedType, 64)
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
			limits = account.Buckets[next.LimitID]
			limits.LimitID = next.LimitID
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
		if next.Name != "" {
			limits.Name = next.Name
		}
		if next.Model != "" {
			limits.Model = next.Model
		}
		limits.ReachedType = next.ReachedType
		if limits.LimitID != "" {
			buckets := make(map[string]protocol.AccountLimits)
			for key, value := range account.Buckets {
				buckets[key] = value
			}
			if len(buckets) < 64 || buckets[limits.LimitID].LimitID != "" {
				buckets[limits.LimitID] = limits
			}
			account.Buckets = buckets
		}
	}
	account.Source = "codex/" + m.Method
	account.ObservedAt = time.Now().UTC()
	a.account = &account
	a.mu.Unlock()
	a.emit(protocol.Event{Kind: "account", Account: &account, RawEvent: m.Method})
	return true
}

func boundBuckets(input map[string]protocol.AccountLimits) map[string]protocol.AccountLimits {
	if input == nil {
		return nil
	}
	result := make(map[string]protocol.AccountLimits)
	keys := make([]string, 0, len(input))
	for key := range input {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if len(result) >= 64 {
			break
		}
		value := input[key]
		boundLimits(&value)
		result[protocol.Clip(key, 128)] = value
	}
	return result
}
