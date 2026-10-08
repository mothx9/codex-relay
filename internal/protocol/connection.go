package protocol

import (
	"context"
	"github.com/gorilla/websocket"
	"sync"
	"time"
)

const PingInterval = 10 * time.Second
const PeerTimeout = 30 * time.Second

// Peer has one reader and one writer, bounded outbound memory, and closes slow peers.
type Peer struct {
	Conn *websocket.Conn
	Send chan Message
	Done chan struct{}
	once sync.Once
}

func NewPeer(c *websocket.Conn) *Peer {
	p := &Peer{Conn: c, Send: make(chan Message, 128), Done: make(chan struct{})}
	c.SetReadLimit(MaxMessage)
	_ = c.SetReadDeadline(time.Now().Add(PeerTimeout))
	c.SetPongHandler(func(string) error { return c.SetReadDeadline(time.Now().Add(PeerTimeout)) })
	return p
}
func (p *Peer) Close() { p.once.Do(func() { close(p.Done); _ = p.Conn.Close() }) }
func (p *Peer) Enqueue(m Message) bool {
	select {
	case <-p.Done:
		return false
	default:
	}
	select {
	case p.Send <- m:
		return true
	default:
		p.Close()
		return false
	}
}
func (p *Peer) WriteLoop(ctx context.Context) {
	t := time.NewTicker(PingInterval)
	defer t.Stop()
	defer p.Close()
	for {
		select {
		case <-ctx.Done():
			return
		case <-p.Done:
			return
		case m := <-p.Send:
			_ = p.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if p.Conn.WriteJSON(m) != nil {
				return
			}
		case <-t.C:
			if p.Conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(10*time.Second)) != nil {
				return
			}
		}
	}
}
func (p *Peer) Read() (Message, error) { var m Message; err := p.Conn.ReadJSON(&m); return m, err }
