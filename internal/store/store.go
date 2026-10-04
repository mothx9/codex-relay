// Package store persists only control metadata. No schema accepts conversation text.
package store

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/mothx9/codex-relay/internal/protocol"
	_ "modernc.org/sqlite"
	"os"
	"path/filepath"
	"time"
)

type Store struct{ DB *sql.DB }

func Open(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, err
	}
	if info, err := os.Lstat(path); err == nil && !info.Mode().IsRegular() {
		return nil, fmt.Errorf("database must be a regular file")
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	_ = f.Close()
	if err = os.Chmod(path, 0600); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	s := &Store{db}
	if _, err = db.Exec(`PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=ON;
 CREATE TABLE IF NOT EXISTS machines (id TEXT PRIMARY KEY, metadata TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, machine_id TEXT NOT NULL, metadata TEXT NOT NULL);
 CREATE INDEX IF NOT EXISTS sessions_machine ON sessions(machine_id);
 CREATE TABLE IF NOT EXISTS pending_requests (id TEXT PRIMARY KEY, machine_id TEXT, session_id TEXT, thread_id TEXT, turn_id TEXT, kind TEXT, created_at TEXT, expires_at TEXT, status TEXT);
 CREATE TABLE IF NOT EXISTS agent_tokens (machine_id TEXT PRIMARY KEY, token_hash TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0);
 CREATE TABLE IF NOT EXISTS operator_sessions (token_hash TEXT PRIMARY KEY, expires_at INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS push_subscriptions (endpoint TEXT PRIMARY KEY, subscription TEXT NOT NULL, privacy INTEGER NOT NULL DEFAULT 1);
 CREATE TABLE IF NOT EXISTS notification_events (id TEXT PRIMARY KEY, created_at INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS audit_events (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL, action TEXT NOT NULL, machine_id TEXT, session_id TEXT, command_id TEXT, outcome TEXT);
 CREATE TABLE IF NOT EXISTS configuration (key TEXT PRIMARY KEY, value TEXT);
 `); err != nil {
		_ = db.Close()
		return nil, err
	}
	return s, nil
}
func (s *Store) Close() error  { return s.DB.Close() }
func Hash(token string) string { h := sha256.Sum256([]byte(token)); return hex.EncodeToString(h[:]) }
func (s *Store) Token(machine, token string) error {
	_, e := s.DB.Exec(`INSERT INTO agent_tokens(machine_id,token_hash,revoked) VALUES(?,?,0) ON CONFLICT(machine_id) DO UPDATE SET token_hash=excluded.token_hash,revoked=0`, machine, Hash(token))
	return e
}
func (s *Store) Revoke(machine string) error {
	_, e := s.DB.Exec(`UPDATE agent_tokens SET revoked=1 WHERE machine_id=?`, machine)
	return e
}
func (s *Store) Authenticate(machine, token string) bool {
	var hash string
	return s.DB.QueryRow(`SELECT token_hash FROM agent_tokens WHERE machine_id=? AND revoked=0`, machine).Scan(&hash) == nil && hash == Hash(token)
}
func (s *Store) NewLogin(token string, expires time.Time) error {
	_, e := s.DB.Exec(`INSERT INTO operator_sessions VALUES(?,?)`, Hash(token), expires.Unix())
	return e
}
func (s *Store) Login(token string) (time.Time, bool) {
	var expires int64
	e := s.DB.QueryRow(`SELECT expires_at FROM operator_sessions WHERE token_hash=?`, Hash(token)).Scan(&expires)
	return time.Unix(expires, 0), e == nil && expires > time.Now().Unix()
}
func (s *Store) Logout(token string) error {
	_, e := s.DB.Exec(`DELETE FROM operator_sessions WHERE token_hash=?`, Hash(token))
	return e
}
func (s *Store) SaveMachine(m protocol.Machine) error {
	b, e := json.Marshal(m)
	if e != nil {
		return e
	}
	_, e = s.DB.Exec(`INSERT INTO machines VALUES(?,?) ON CONFLICT(id) DO UPDATE SET metadata=excluded.metadata`, m.ID, string(b))
	return e
}
func (s *Store) SaveSession(v protocol.Session) error {
	b, e := json.Marshal(v)
	if e != nil {
		return e
	}
	_, e = s.DB.Exec(`INSERT INTO sessions VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET machine_id=excluded.machine_id,metadata=excluded.metadata`, v.ID, v.MachineID, string(b))
	return e
}
func (s *Store) ReplaceSessions(machine string, sessions []protocol.Session) error {
	tx, e := s.DB.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	if _, e = tx.Exec(`DELETE FROM sessions WHERE machine_id=?`, machine); e != nil {
		return e
	}
	for _, v := range sessions {
		b, err := json.Marshal(v)
		if err != nil {
			return err
		}
		if _, e = tx.Exec(`INSERT INTO sessions VALUES(?,?,?)`, v.ID, machine, string(b)); e != nil {
			return e
		}
	}
	return tx.Commit()
}
func (s *Store) SavePending(v protocol.PendingRequest) error {
	_, e := s.DB.Exec(`INSERT INTO pending_requests VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,expires_at=excluded.expires_at`, v.ID, v.MachineID, v.SessionID, v.ThreadID, v.TurnID, v.Kind, v.CreatedAt.Format(time.RFC3339Nano), v.ExpiresAt.Format(time.RFC3339Nano), v.Status)
	return e
}
func (s *Store) ClearPending(machine string) error {
	_, e := s.DB.Exec(`DELETE FROM pending_requests WHERE machine_id=?`, machine)
	return e
}
func (s *Store) ResolvePending(id string) error {
	_, e := s.DB.Exec(`DELETE FROM pending_requests WHERE id=?`, id)
	return e
}
func (s *Store) Load() (protocol.Snapshot, error) {
	out := protocol.Snapshot{Machines: []protocol.Machine{}, Sessions: []protocol.Session{}, Requests: []protocol.PendingRequest{}}
	rows, e := s.DB.Query(`SELECT metadata FROM machines`)
	if e != nil {
		return out, e
	}
	for rows.Next() {
		var raw string
		var m protocol.Machine
		if e = rows.Scan(&raw); e != nil {
			rows.Close()
			return out, e
		}
		if e = json.Unmarshal([]byte(raw), &m); e != nil {
			rows.Close()
			return out, e
		}
		m.Status = protocol.Offline
		out.Machines = append(out.Machines, m)
	}
	e = rows.Err()
	rows.Close()
	if e != nil {
		return out, e
	}
	rows, e = s.DB.Query(`SELECT metadata FROM sessions`)
	if e != nil {
		return out, e
	}
	defer rows.Close()
	for rows.Next() {
		var raw string
		var v protocol.Session
		if e = rows.Scan(&raw); e != nil {
			return out, e
		}
		if e = json.Unmarshal([]byte(raw), &v); e != nil {
			return out, e
		}
		v.ReadOnly = true
		out.Sessions = append(out.Sessions, v)
	}
	return out, rows.Err()
}
func (s *Store) Audit(action, machine, session, command, outcome string) error {
	_, e := s.DB.Exec(`INSERT INTO audit_events(timestamp,action,machine_id,session_id,command_id,outcome) VALUES(?,?,?,?,?,?)`, time.Now().UTC().Format(time.RFC3339Nano), action, machine, session, command, outcome)
	return e
}
func (s *Store) NotifyOnce(id string) (bool, error) {
	r, e := s.DB.Exec(`INSERT OR IGNORE INTO notification_events VALUES(?,?)`, id, time.Now().Unix())
	if e != nil {
		return false, e
	}
	n, e := r.RowsAffected()
	return n > 0, e
}
func (s *Store) Prune() error {
	_, e := s.DB.Exec(`DELETE FROM operator_sessions WHERE expires_at<unixepoch(); DELETE FROM audit_events WHERE id NOT IN (SELECT id FROM audit_events ORDER BY id DESC LIMIT 1000); DELETE FROM notification_events WHERE id NOT IN (SELECT id FROM notification_events ORDER BY created_at DESC LIMIT 8192)`)
	return e
}

type PushSubscription struct {
	Endpoint string
	JSON     []byte
	Privacy  bool
}

func (s *Store) Subscribe(v PushSubscription) error {
	var count int
	if e := s.DB.QueryRow(`SELECT count(*) FROM push_subscriptions`).Scan(&count); e != nil {
		return e
	}
	var existing int
	_ = s.DB.QueryRow(`SELECT count(*) FROM push_subscriptions WHERE endpoint=?`, v.Endpoint).Scan(&existing)
	if count >= 32 && existing == 0 {
		return fmt.Errorf("push subscription limit reached")
	}
	_, e := s.DB.Exec(`INSERT INTO push_subscriptions VALUES(?,?,?) ON CONFLICT(endpoint) DO UPDATE SET subscription=excluded.subscription,privacy=excluded.privacy`, v.Endpoint, string(v.JSON), v.Privacy)
	return e
}
func (s *Store) Unsubscribe(endpoint string) error {
	_, e := s.DB.Exec(`DELETE FROM push_subscriptions WHERE endpoint=?`, endpoint)
	return e
}
func (s *Store) Subscriptions() ([]PushSubscription, error) {
	rows, e := s.DB.Query(`SELECT endpoint,subscription,privacy FROM push_subscriptions`)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := []PushSubscription{}
	for rows.Next() {
		var v PushSubscription
		var raw string
		if e = rows.Scan(&v.Endpoint, &raw, &v.Privacy); e != nil {
			return nil, e
		}
		v.JSON = []byte(raw)
		out = append(out, v)
	}
	return out, rows.Err()
}
