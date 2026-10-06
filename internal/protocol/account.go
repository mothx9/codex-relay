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
	LimitID             string        `json:"limitId,omitempty"`
	Plan                string        `json:"planType,omitempty"`
	Primary             *RateWindow   `json:"primary,omitempty"`
	Secondary           *RateWindow   `json:"secondary,omitempty"`
	Credits             *Credits      `json:"credits,omitempty"`
	IndividualLimit     *SpendControl `json:"individualLimit,omitempty"`
	SpendControlReached *bool         `json:"spendControlReached,omitempty"`
}
type TokenBreakdown struct {
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
