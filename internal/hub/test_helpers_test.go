package hub

import (
	"net"
	"os"
)

func writeTestSecret(path, token string) error     { return os.WriteFile(path, []byte(token), 0600) }
func listenTest(addr string) (net.Listener, error) { return net.Listen("tcp", addr) }
