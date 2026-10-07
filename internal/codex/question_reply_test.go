package codex

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestQuestionReplyPresentationPreservesCanonicalIdentity(t *testing.T) {
	source := `<send_user_message_question_reply>
[{"answer":"Keep it","question":"Keep ` + "`test-123`" + `?","questionItemId":"upstream-id"}]
</send_user_message_question_reply>`
	raw, _ := json.Marshal(map[string]any{"id": "canonical", "clientId": "client", "type": "userMessage", "content": []map[string]string{{"type": "text", "text": source}}})
	got := activity(raw)
	if got.ID != "canonical" || got.ClientID != "client" || got.Kind != "userMessage" || got.Text != "Keep it" || len(got.Replies) != 1 || got.Replies[0].Question != "Keep `test-123`?" {
		t.Fatalf("bad projection: %+v", got)
	}
	for _, invalid := range []string{"Example: " + source, source + " extra", strings.Replace(source, "\"answer\":\"Keep it\"", "\"answer\":42", 1), strings.Replace(source, "upstream-id", "", 1), "<send_user_message_question_reply>[]</send_user_message_question_reply>"} {
		if questionReply(invalid) != nil {
			t.Fatal("unrecognized content normalized", invalid)
		}
	}
}
