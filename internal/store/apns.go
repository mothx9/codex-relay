package store

import (
	"encoding/hex"
	"errors"
)

type APNSSubscription struct {
	DeviceID, Token, Environment string
	Privacy                      bool
}

func (s *Store) SubscribeAPNS(sub APNSSubscription) error {
	if sub.Environment != "sandbox" && sub.Environment != "production" {
		return errors.New("invalid APNs environment")
	}
	if len(sub.Token) < 32 || len(sub.Token) > 512 {
		return errors.New("invalid APNs token")
	}
	if _, err := hex.DecodeString(sub.Token); err != nil {
		return errors.New("invalid APNs token")
	}
	res, err := s.DB.Exec(`INSERT INTO apns_subscriptions SELECT id,?,?,? FROM operator_devices WHERE id=? AND revoked=0 AND expires_at>unixepoch() ON CONFLICT(device_id) DO UPDATE SET token=excluded.token,environment=excluded.environment,privacy=excluded.privacy`, sub.Token, sub.Environment, sub.Privacy, sub.DeviceID)
	if err != nil {
		return err
	}
	count, _ := res.RowsAffected()
	if count != 1 {
		return errors.New("device access unavailable")
	}
	return nil
}
func (s *Store) UnsubscribeAPNS(id string) error {
	_, err := s.DB.Exec(`DELETE FROM apns_subscriptions WHERE device_id=?`, id)
	return err
}
func (s *Store) APNSSubscriptions() ([]APNSSubscription, error) {
	rows, err := s.DB.Query(`SELECT p.device_id,p.token,p.environment,p.privacy FROM apns_subscriptions p JOIN operator_devices d ON d.id=p.device_id WHERE d.revoked=0 AND d.expires_at>unixepoch()`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []APNSSubscription{}
	for rows.Next() {
		var sub APNSSubscription
		if err = rows.Scan(&sub.DeviceID, &sub.Token, &sub.Environment, &sub.Privacy); err != nil {
			return nil, err
		}
		out = append(out, sub)
	}
	return out, rows.Err()
}

// NotificationState reads only durable routing metadata, never transcript/form content.
func (s *Store) NotificationState(requestID string) (count int, pending bool, err error) {
	var present int
	err = s.DB.QueryRow(`SELECT count(*), coalesce(max(CASE WHEN id=? THEN 1 ELSE 0 END),0) FROM pending_requests`, requestID).Scan(&count, &present)
	return count, present != 0, err
}
