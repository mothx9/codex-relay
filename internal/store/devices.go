package store

import (
	"errors"
	"time"
)

type Device struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
	ExpiresAt time.Time `json:"expires_at"`
	LastSeen  time.Time `json:"last_seen"`
	Revoked   bool      `json:"revoked"`
}

func (s *Store) AddDevice(id, name, token string, expires time.Time) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var count int
	if err = tx.QueryRow(`SELECT count(*) FROM operator_devices`).Scan(&count); err != nil {
		return err
	}
	if count >= 32 {
		return errors.New("device limit reached; remove expired devices first")
	}
	now := time.Now().Unix()
	_, err = tx.Exec(`INSERT INTO operator_devices VALUES(?,?,?,?,?,?,0)`, id, name, Hash(token), now, expires.Unix(), now)
	if err != nil {
		return err
	}
	return tx.Commit()
}
func (s *Store) DeviceLogin(token string) (string, time.Time, bool) {
	var id string
	var expires int64
	err := s.DB.QueryRow(`SELECT id,expires_at FROM operator_devices WHERE token_hash=? AND revoked=0`, Hash(token)).Scan(&id, &expires)
	return id, time.Unix(expires, 0), err == nil && expires > time.Now().Unix()
}
func (s *Store) OperatorLogin(token string) (string, time.Time, bool) {
	if id, expires, ok := s.DeviceLogin(token); ok {
		return id, expires, true
	}
	expires, ok := s.Login(token)
	return "", expires, ok
}
func (s *Store) TouchDevice(token string) error {
	_, err := s.DB.Exec(`UPDATE operator_devices SET last_seen=unixepoch() WHERE token_hash=? AND revoked=0`, Hash(token))
	return err
}
func (s *Store) Devices() ([]Device, error) {
	rows, err := s.DB.Query(`SELECT id,name,created_at,expires_at,last_seen,revoked FROM operator_devices ORDER BY created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Device{}
	for rows.Next() {
		var v Device
		var created, expires, seen int64
		if err = rows.Scan(&v.ID, &v.Name, &created, &expires, &seen, &v.Revoked); err != nil {
			return nil, err
		}
		v.CreatedAt = time.Unix(created, 0).UTC()
		v.ExpiresAt = time.Unix(expires, 0).UTC()
		v.LastSeen = time.Unix(seen, 0).UTC()
		out = append(out, v)
	}
	return out, rows.Err()
}
func (s *Store) RevokeDevice(id string) error {
	_, err := s.DB.Exec(`UPDATE operator_devices SET revoked=1 WHERE id=?`, id)
	return err
}
func (s *Store) RevokeDeviceToken(token string) error {
	_, err := s.DB.Exec(`UPDATE operator_devices SET revoked=1 WHERE token_hash=?`, Hash(token))
	return err
}
func (s *Store) RemoveDevice(id string) error {
	_, err := s.DB.Exec(`DELETE FROM operator_devices WHERE id=?`, id)
	return err
}
func (s *Store) SetPaused(id string, paused bool) error {
	_, err := s.DB.Exec(`INSERT INTO machine_access VALUES(?,?) ON CONFLICT(machine_id) DO UPDATE SET paused=excluded.paused`, id, paused)
	return err
}
func (s *Store) MachineAccess(id string) string {
	var revoked bool
	var paused bool
	err := s.DB.QueryRow(`SELECT t.revoked,coalesce(a.paused,0) FROM agent_tokens t LEFT JOIN machine_access a ON a.machine_id=t.machine_id WHERE t.machine_id=?`, id).Scan(&revoked, &paused)
	if err != nil || revoked {
		return "REVOKED"
	}
	if paused {
		return "PAUSED"
	}
	return "ALLOWED"
}

// Enrollment never replaces an existing credential silently.
func (s *Store) EnrollMachine(id, token string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var count int
	if err = tx.QueryRow(`SELECT count(*) FROM agent_tokens WHERE revoked=0`).Scan(&count); err != nil {
		return err
	}
	if count >= 16 {
		return errors.New("machine limit reached")
	}
	_, err = tx.Exec(`INSERT INTO agent_tokens VALUES(?,?,0) ON CONFLICT(machine_id) DO UPDATE SET token_hash=excluded.token_hash,revoked=0 WHERE agent_tokens.revoked=1`, id, Hash(token))
	if err != nil {
		return err
	}
	var hash string
	if err = tx.QueryRow(`SELECT token_hash FROM agent_tokens WHERE machine_id=?`, id).Scan(&hash); err != nil || hash != Hash(token) {
		return errors.New("machine already enrolled")
	}
	if _, err = tx.Exec(`DELETE FROM machine_access WHERE machine_id=?`, id); err != nil {
		return err
	}
	return tx.Commit()
}
func (s *Store) RemoveMachine(id string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, query := range []string{`UPDATE agent_tokens SET revoked=1 WHERE machine_id=?`, `DELETE FROM machines WHERE id=?`, `DELETE FROM sessions WHERE machine_id=?`, `DELETE FROM pending_requests WHERE machine_id=?`, `DELETE FROM machine_access WHERE machine_id=?`} {
		if _, err = tx.Exec(query, id); err != nil {
			return err
		}
	}
	return tx.Commit()
}
