package protocol

const (
	NewTurn               = "new_turn"
	QueueUpdate           = "queue_update"
	QueueSteer            = "queue_steer"
	FollowUpCommand       = "follow_up"
	Steer                 = "steer"
	Answer                = "answer"
	Interrupt             = "interrupt"
	TurnChanged           = "TURN_CHANGED"
	NotSteerable          = "NOT_STEERABLE"
	FollowUpUnavailable   = "FOLLOW_UP_UNAVAILABLE"
	SessionReadOnly       = "SESSION_READ_ONLY"
	MachineOffline        = "MACHINE_OFFLINE"
	PendingRequestChanged = "PENDING_REQUEST_CHANGED"
	QueueChanged          = "QUEUE_CHANGED"
	CodexDisconnected     = "CODEX_DISCONNECTED"
	CodexRejected         = "CODEX_REJECTED"
	UnknownOutcome        = "UNKNOWN_OUTCOME"
)

// Accept earlier RC wire names during upgrade; all new clients use canonical names.
func CommandKind(kind string) string {
	switch kind {
	case "start":
		return NewTurn
	case "queue":
		return FollowUpCommand
	case "respond":
		return Answer
	}
	return kind
}

func Failure(c Command, code string) Result {
	message := "Codex ha rifiutato il comando. Il testo resta disponibile."
	retryable := false
	switch code {
	case TurnChanged:
		message = "Il turno è cambiato. Scegli esplicitamente come inviare il testo."
	case NotSteerable:
		message = "Il turno corrente non consente Steer."
	case FollowUpUnavailable:
		message = "Il follow-up non è disponibile per questa sessione."
	case SessionReadOnly:
		message = "Sessione in sola lettura. Collegala prima di inviare messaggi."
	case MachineOffline:
		message = "Macchina offline. Il comando non è stato inviato."
		retryable = true
	case PendingRequestChanged:
		message = "La richiesta è stata risolta, è scaduta o sta già ricevendo una risposta."
	case QueueChanged:
		message = "La queue Codex è cambiata. Verifica il contesto prima di riprovare."
	case CodexDisconnected:
		message = "Codex è disconnesso. Il comando non è stato inviato."
		retryable = true
	case UnknownOutcome:
		message = "Esito sconosciuto. Verifica il thread Codex prima di decidere se reinviare."
	default:
		code = CodexRejected
	}
	return Result{ID: c.ID, SessionID: c.SessionID, ErrorCode: code, Error: message, Retryable: retryable}
}

// Adapter capabilities are explicit; status alone never grants control.
func CheckControl(s Session, c Command) string {
	if len(c.Images) > 0 && (!s.Capabilities.CanSendImages || (CommandKind(c.Kind) != NewTurn && CommandKind(c.Kind) != FollowUpCommand && CommandKind(c.Kind) != Steer)) {
		return CodexRejected
	}

	if s.ReadOnly {
		return SessionReadOnly
	}
	switch CommandKind(c.Kind) {
	case NewTurn:
		if s.Status != Ready {
			return TurnChanged
		}
		if !s.Capabilities.CanSend {
			return SessionReadOnly
		}
	case QueueUpdate:
		if !s.Capabilities.CanEditQueue {
			return FollowUpUnavailable
		}
	case FollowUpCommand:
		if s.Status != Working || !s.Capabilities.CanFollowUp {
			return FollowUpUnavailable
		}
	case Steer:
		if c.TurnID != "" && c.TurnID != s.TurnID {
			return TurnChanged
		}
		if s.Status != Working || s.TurnID == "" || c.TurnID == "" || !s.Capabilities.CanSteer {
			return NotSteerable
		}
	case QueueSteer:
		if !s.Capabilities.CanSteerQueue {
			return FollowUpUnavailable
		}
		if c.TurnID != s.TurnID {
			return TurnChanged
		}
		if s.Status != Working || s.TurnID == "" || !s.Capabilities.CanSteer {
			return NotSteerable
		}
	case Interrupt:
		if s.TurnID == "" || c.TurnID != s.TurnID || !s.Capabilities.CanInterrupt {
			return TurnChanged
		}
	}
	return ""
}
