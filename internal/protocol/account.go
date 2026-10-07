package protocol

import "time"

// Explicit allowlisted Codex accounting data. No auth fields or opaque payloads.
type RateWindow struct {
	UsedPercent   int    `json:"usedPercent"`
	WindowMinutes *int64 `json:"windowDurationMins,omitempty"`
	ResetsAt      *int64 `json:"resetsAt,omitempty"`
}
type Credits struct {
	HasCredits bool    `json:"hasCredits"`
	Unlimited  bool    `json:"unlimited"`
	Balance    *string `json:"balance,omitempty"`
}
type SpendControl struct {
	Limit            string `json:"limit"`
	Used             string `json:"used"`
	RemainingPercent int    `json:"remainingPercent"`
	ResetsAt         int64  `json:"resetsAt"`
}
type AccountLimits struct {
	Name                string        `json:"limitName,omitempty"`
	Model               string        `json:"normalModelSlug,omitempty"`
	ReachedType         string        `json:"rateLimitReachedType,omitempty"`
	LimitID             string        `json:"limitId,omitempty"`
	Plan                string        `json:"planType,omitempty"`
	Primary             *RateWindow   `json:"primary,omitempty"`
	Secondary           *RateWindow   `json:"secondary,omitempty"`
	Credits             *Credits      `json:"credits,omitempty"`
	IndividualLimit     *SpendControl `json:"individualLimit,omitempty"`
	SpendControlReached *bool         `json:"spendControlReached,omitempty"`
}
type TokenBreakdown struct {
	ReasoningOutput int64 `json:"reasoningOutputTokens"`
	Input           int64 `json:"inputTokens"`
	CachedInput     int64 `json:"cachedInputTokens"`
	CacheWriteInput int64 `json:"cacheWriteInputTokens"`
	Output          int64 `json:"outputTokens"`
	Total           int64 `json:"totalTokens"`
}
type TokenUsage struct {
	Last          TokenBreakdown `json:"last"`
	Total         TokenBreakdown `json:"total"`
	ContextWindow *int64         `json:"modelContextWindow,omitempty"`
	ObservedAt    time.Time      `json:"observed_at"`
	Source        string         `json:"source"`
}

// Only display metadata; reset-credit redemption remains local to Codex.
type ResetCredits struct {
	Available int64         `json:"availableCount"`
	Credits   []ResetCredit `json:"credits"`
}
type ResetCredit struct {
	ID          string  `json:"id"`
	Title       *string `json:"title,omitempty"`
	Description *string `json:"description,omitempty"`
	ExpiresAt   *int64  `json:"expiresAt,omitempty"`
	GrantedAt   int64   `json:"grantedAt"`
	ResetType   string  `json:"resetType"`
	Status      string  `json:"status"`
}
