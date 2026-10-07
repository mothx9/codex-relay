package codex

import (
	"encoding/json"
	"strings"

	"github.com/mothx9/codex-relay/internal/protocol"
)

// Normalize only the complete, well-formed upstream envelope. This is a
// presentation projection, never evidence that a pending RPC was resolved.
// Mixed prose and malformed envelopes remain untouched; Codex owns the source.
func questionReply(text string) []protocol.QuestionReply {
	const opening = "<send_user_message_question_reply>"
	const closing = "</send_user_message_question_reply>"
	source := strings.TrimSpace(text)
	if len(source) > protocol.MaxText || !strings.HasPrefix(source, opening) || !strings.HasSuffix(source, closing) {
		return nil
	}
	var entries []struct {
		Answer         *string `json:"answer"`
		Question       *string `json:"question"`
		QuestionItemID string  `json:"questionItemId"`
	}
	body := strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(source, opening), closing))
	if json.Unmarshal([]byte(body), &entries) != nil || len(entries) == 0 || len(entries) > 16 {
		return nil
	}
	replies := make([]protocol.QuestionReply, 0, len(entries))
	for _, entry := range entries {
		if entry.Answer == nil || entry.Question == nil || strings.TrimSpace(*entry.Question) == "" || entry.QuestionItemID == "" {
			return nil
		}
		replies = append(replies, protocol.QuestionReply{Question: *entry.Question, Answer: *entry.Answer})
	}
	return replies
}
